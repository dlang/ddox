/**
	Directly parses D source code using libdparse.

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.parsers.dparse;

import ddox.ddox;
import ddox.entities;
import dparse = std.d.parser;
import dlex = std.d.lexer;
import dformat = std.d.formatter;

import std.algorithm;
import std.conv;
import std.exception;
import std.range;
import std.stdio;
import std.string;
import std.typecons;
import core.demangle;
import vibe.core.log;
import vibe.data.json;

// random dparser notes:
//   Declaration.declarations[] ?
//   Strings should be const(char)[] instead of string if transient
//   how to get token name by token
//   convenience functions for Formatter and unDecorateComment
//   ambiguous representation of mutually exclusive values (maybe use subclassing? or enums for disambiguation?)
//   InterfaceDecl.baseClassList <-> baseInterfaceList
//   start/end line/column values for every AST node


Package parseD(string[] d_files, Package root = null)
{
	if (!root) root = new Package(null, null);
	DParser p;
	foreach (file; d_files)
		p.parseModule(file, root);
	p.resolveTypes(root);
	return root;
}


private struct DParser
{
	private Tuple!(Type, Entity)[] m_primTypes;
	private Declaration[string] m_typeMap;

	void resolveTypes(Package root)
	{
		bool isTypeDecl(Declaration a)
		{
			switch(a.kind){
				default: return false;
				case DeclarationKind.Struct:
				case DeclarationKind.Union:
				case DeclarationKind.Class:
				case DeclarationKind.Interface:
				case DeclarationKind.Enum:
					return true;
				case DeclarationKind.Alias:
					return (cast(AliasDeclaration)a).targetType !is null;
				case DeclarationKind.TemplateParameter:
					return true;
				case DeclarationKind.Template:
					// support eponymous template types
					auto td = cast(TemplateDeclaration)a;
					// be optimistic for templates without content that they are in fact types
					if (!td.members.length) return true;
					// otherwise require an actual eponymous type member
					auto mi = td.members.countUntil!(m => m.name == a.name);
					return mi >= 0 && isTypeDecl(td.members[mi]);
			}
		}

		foreach (t; m_primTypes) {
			auto decl = t[1].lookup!Declaration(t[0].typeName);
			if (!decl || !isTypeDecl(decl)) {
				auto pd = t[0].typeName in m_typeMap;
				if (pd) decl = *pd;
			}
			if (decl && isTypeDecl(decl))
				t[0].typeDecl = decl;
		}

		// fixup class bases
		root.visit!ClassDeclaration((decl){
			if (decl.baseClass && decl.baseClass.typeDecl && !cast(ClassDeclaration)decl.baseClass.typeDecl)
				decl.baseClass.typeDecl = null;
			
			foreach (ref i; decl.derivedInterfaces) {
				if (i.typeDecl && !decl.baseClass && cast(ClassDeclaration)i.typeDecl) {
					decl.baseClass = i;
					i = null;
				} else if (i.typeDecl && !cast(InterfaceDeclaration)i.typeDecl) {
					i.typeDecl = null;
				}
			}

			decl.derivedInterfaces = decl.derivedInterfaces.filter!(i => i !is null).array;

			assert(decl);
		});

		// fixup interface bases
		root.visit!InterfaceDeclaration((decl){
			foreach( i; decl.derivedInterfaces )
				if( i.typeDecl && !cast(InterfaceDeclaration)i.typeDecl )
					i.typeDecl = null;
			assert(decl);
		});
	}

	void parseModule(string filename, Package root_package)
	{
		import std.file;

		dlex.LexerConfig config;
		config.fileName = filename;
		config.stringBehavior = dlex.StringBehavior.source;
		dlex.StringCache cache = dlex.StringCache(1024 * 4);
		auto tokens = dlex.getTokensForParser(cast(ubyte[])std.file.read(filename), config, &cache).array;
		auto dmod = dparse.parseModule(tokens, filename);

		Module mod;
		if (!dmod.moduleDeclaration) {
			logError("No module declaration in module %s - ignoring", filename);
			return;
		}

		auto path = dmod.moduleDeclaration.moduleName.identifiers.map!(a => a.text.idup).array;
		logInfo("MOD %s", path);
		Package p = root_package;
		foreach (i, pe; path) {
			if (i+1 < path.length) p = p.getOrAddPackage(pe);
			else mod = p.createModule(pe);
		}

		mod.file = filename;
		mod.docGroup = new DocGroup(mod, dmod.moduleDeclaration.comment.undecorateComment());
		mod.members = parseDeclList(dmod.declarations, mod);
	}

	Declaration[] parseDeclList(dparse.Declaration[] decls, Entity parent)
	{
		DocGroup lastdoc;
		Declaration[] ret;
		foreach (mem; decls) {
			foreach (decl; parseDecl(mem, parent)) {
				auto doc = decl.docGroup;
				if (lastdoc && (doc.text == lastdoc.text && doc.text.length || doc.comment.isDitto)) {
					lastdoc.members ~= decl;
					decl.docGroup = lastdoc;
				} else if (doc.comment.isPrivate) {
					decl.protection = Protection.Private;
					lastdoc = null;
				} else lastdoc = decl.docGroup;
				ret ~= decl;
			}
		}
		return ret;
	}

	Declaration[] parseDecl(dparse.Declaration decl, Entity parent, dparse.Attribute[] additional_attribs = null)
	{
		if (auto ad = decl.attributeDeclaration) {
			additional_attribs ~= decl.attributes;
			additional_attribs ~= ad.attribute;
			return decl.declarations.map!(d => parseDecl(decl, parent, additional_attribs)).join();
		}
		
		Declaration ret;
		string comment;
		int line;
		if (auto fd = decl.functionDeclaration) {
			comment = fd.comment.undecorateComment();
			ret = parseFunctionDecl(fd, parent);
		} else if (auto vd = decl.variableDeclaration) {
			// TODO
		} else if (auto at = decl.aliasThisDeclaration) {
			// TODO
		} else if (auto sd = decl.structDeclaration) {
			// TODO
		} else if (auto cd = decl.classDeclaration) {
			comment = cd.comment.undecorateComment();
			line = cd.name.line;
			auto cdr = new ClassDeclaration(parent, cd.name.text.idup);
			if (cd.baseClassList) foreach (bc; cd.baseClassList.items) {
				auto t = new Type;
				t.kind = TypeKind.Primitive;
				t.typeName = formatNode(bc);
				cdr.derivedInterfaces ~= t;
				m_primTypes ~= tuple(t, parent);
			}
			cdr.members = parseDeclList(cd.structBody.declarations, cdr);
			insertIntoTypeMap(cdr);
			ret = cdr;
		} else if (auto id = decl.interfaceDeclaration) {
			comment = cd.comment.undecorateComment();
			line = id.name.line;
			auto idr = new InterfaceDeclaration(parent, id.name.text.idup);
			if (id.baseClassList) foreach (bc; id.baseClassList.items) {
				auto t = new Type;
				t.kind = TypeKind.Primitive;
				t.typeName = formatNode(bc);
				idr.derivedInterfaces ~= t;
				m_primTypes ~= tuple(t, parent);
			}
			idr.members = parseDeclList(id.structBody.declarations, idr);
			insertIntoTypeMap(idr);
			ret = idr;
		} else if (auto ud = decl.unionDeclaration) {
			// TODO
		} else if (auto ed = decl.enumDeclaration) {
			// TODO
		} else if (auto ad = decl.aliasDeclaration) {
			// TODO
		} else if (auto td = decl.templateDeclaration) {
			// TODO
		} else if (auto cd = decl.constructor) {
			// TODO
		} else if (auto dd = decl.destructor) {
			// TODO
		} else if (auto scd = decl.staticConstructor) {
			// TODO
		} else if (auto sdd = decl.staticDestructor) {
			// TODO
		} else if (auto pbd = decl.postblit) {
			// TODO
		} else if (auto id = decl.importDeclaration) {
			// TODO: use for type resolution
		} else if (auto id = decl.staticImportDeclaration) {
			// TODO: use for type resolution
		}

		if (!ret) return null;

		assert(comment !is null);

		ret.line = 
		ret.docGroup = new DocGroup(cdr, comment);
		addAttributes(ret, additional_attribs);
		addAttributes(ret, decl.attributes);
		return [ret];
	}

	void addAttributes(Declaration decl, dparse.Attribute[] attrs)
	{
		foreach (att; attrs) {
			auto as = formatNode(att);
			switch (as) {
				default:
					decl.attributes ~= as;
					break;
				case "private": decl.protection = Protection.Private; break;
				case "package": decl.protection = Protection.Package; break;
				case "protected": decl.protection = Protection.Protected; break;
				case "public": decl.protection = Protection.Public; break;
			}
		}
	}

	Declaration parseFunctionDecl(dparse.FunctionDeclaration ddecl, Entity parent)
	{
		auto ret = new FunctionDeclaration(parent, ddecl.name.text.idup);
		ret.line = ddecl.name.line;
		ret.returnType = parseType(ddecl.returnType, parent);

		addAttributes(ret, ddecl.attributes);

		ret.parameters = parseParameters(ddecl.parameters, ret);
		ret.type = new Type;
		ret.type.kind = TypeKind.Function;
		//ret.type.attributes = ...; // TODO!
		//ret.type.modifiers = ...; // TODO!
		ret.type.returnType = ret.returnType;
		ret.type.parameterTypes = ret.parameters.map!(p => p.type).array;

		if (auto ta = ddecl.templateParameters) {
			ret.isTemplate = true;
			if (auto tpl = ta.templateParameterList)
				ret.templateArgs = tpl.items.map!(tp => new TemplateParameterDeclaration(ret, formatNode(tp))).array;
		}

		return ret;
	}

	VariableDeclaration[] parseParameters(dparse.Parameters dparams, FunctionDeclaration parent)
	{
		VariableDeclaration[] ret;
		foreach (p; dparams.parameters) {
			ret ~= parseParameter(p, parent);
			if (p.vararg) ret[$-1].name ~= "...";
		}
		if (dparams.hasVarargs)
			ret ~= new VariableDeclaration(parent, "...");
		return ret;
	}

	VariableDeclaration parseParameter(dparse.Parameter dparam, FunctionDeclaration parent)
	{
		auto ret = new VariableDeclaration(parent, dparam.name.text.idup);
		ret.type = parseType(dparam.type, parent);
		if (dparam.default_) {
			ret.initializer = new Value;
			ret.initializer.type = ret.type;
			ret.initializer.valueString = formatNode(dparam.default_);
		}
		
		return ret;
	}

	Type parseType(dparse.Type type, Entity scope_)
	{
		auto ret = parseType(type.type2, scope_);
		foreach (tc; type.typeConstructors)
			ret.modifiers ~= dlex.str(tc);

		foreach (sf; type.typeSuffixes) {
			if (sf.delegateOrFunction.text) {
				if (sf.delegateOrFunction.text == "function")
					ret = Type.makeFunction(ret, parseParameters(sf.parameters, null).map!(p => p.type).array);
				else ret = Type.makeDelegate(ret, parseParameters(sf.parameters, null).map!(p => p.type).array);
			}
			else if (sf.star) ret = Type.makePointer(ret);
			else if (sf.array) ret = Type.makeArray(ret); // FIXME: SA? AA?
		}

		return ret;
	}

	Type parseType(dparse.Type2 type, Entity scope_)
	{
		auto ret = new Type;
		if (type.builtinType) {
			ret.kind = TypeKind.Primitive;
			ret.typeName = dlex.str(type.builtinType);
		} else if (type.symbol) {
			ret.kind = TypeKind.Primitive;
			ret.typeName = formatNode(type.symbol);
			m_primTypes ~= tuple(ret, scope_);
		} else if (auto te = type.typeofExpression) {
			ret.kind = TypeKind.Primitive;
			ret.typeName = formatNode(te.expression);
			// te.return_?
		} else if (auto itc = type.identifierOrTemplateChain) {
			ret.kind = TypeKind.Primitive;
			ret.typeName = itc.identifiersOrTemplateInstances
				.map!(it => it.templateInstance ? formatNode(it.templateInstance) : it.identifier.text.idup)
				.join(".");
			m_primTypes ~= tuple(ret, scope_);
		} else if (auto tc = type.typeConstructor) {
			ret.kind = TypeKind.Primitive;
			ret.typeName = dlex.str(tc);
		} else if (auto tp = type.type) {
			return parseType(tp, scope_);
		} else {
			ret.kind = TypeKind.Primitive;
			ret.typeName = "(invalid)";
		}
		return ret;
	}

	void insertIntoTypeMap(Declaration decl)
	{
		string[] parts = split(decl.qualifiedName, ".");
		foreach( i; 0 .. parts.length ){
			auto partial_name = join(parts[i .. $], ".");
			m_typeMap[partial_name] = decl;
		}
	}
}


private string undecorateComment(string str)
{
	if (!str.length) return str;

	auto app = appender!string();
	dlex.unDecorateComment(str, app);
	return app.data;
}


private string formatNode(T)(const T t)
{
	import std.array;
	auto writer = appender!string();
	auto formatter = new dformat.Formatter!(typeof(writer))(writer);
	formatter.format(t);
	return writer.data;
}
