/**
	Directly parses D source code using libdparse.

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.parsers.dparse;

import ddox.ddox;
import ddox.entities;
import dparse = dparse.parser;
import dlex = dparse.lexer;
import dformat = dparse.formatter;
import dparse.rollback_allocator : RollbackAllocator;

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
//   doc comments for alias this
//   Declaration.attributeDeclaration vs. .attributes and .declarations?
//   AliasDeclaration direct fields vs. initializers?
//   Alias to non-type declarations is a type?


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
	private Tuple!(CachedType, Rebindable!(const(Entity)))[] m_primTypes;
	private Declaration[string] m_typeMap;

	void resolveTypes(Package root)
	{
		bool isTypeDecl(const(Declaration) a)
		{
			switch (a.kind) {
				default: return false;
				case DeclarationKind.Struct:
				case DeclarationKind.Union:
				case DeclarationKind.Class:
				case DeclarationKind.Interface:
				case DeclarationKind.Enum:
					return true;
				case DeclarationKind.Alias:
					return !!(cast(AliasDeclaration)a).targetType;
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

		foreach (ref t; m_primTypes) {
			Rebindable!(const(Declaration)) decl = t[1].lookup!Declaration(t[0].typeName);
			if (!decl || !isTypeDecl(decl)) {
				auto pd = t[0].typeName in m_typeMap;
				if (pd) decl = *pd;
			}
			if (decl && isTypeDecl(decl)) {
				Type tp = t[0];
				tp.typeDecl = decl;
				t[0] = tp;
			}
		}

		// fixup class bases
		root.visit!ClassDeclaration((ClassDeclaration decl){
			if (decl.baseClass && decl.baseClass.typeDecl && !cast(ClassDeclaration)decl.baseClass.typeDecl) {
				Type t = decl.baseClass;
				t.typeDecl = null;
				decl.baseClass = t;
			}

			if (!decl.baseClass) {
				auto idx = decl.derivedInterfaces.countUntil!(i => cast(ClassDeclaration)i.typeDecl !is null);
				if (idx >= 0) decl.baseClass = decl.derivedInterfaces[idx];
			}

			decl.derivedInterfaces = decl.derivedInterfaces
				.filter!(i => !!i)
				.map!((i) {
					if (i.typeDecl && !cast(InterfaceDeclaration)i.typeDecl) {
						Type tp = i;
						tp.typeDecl = null;
						return CachedType(tp);
					} else return i;
				})
				.array;

			assert(decl);
		});

		// fixup interface bases
		root.visit!InterfaceDeclaration((InterfaceDeclaration decl){
			decl.derivedInterfaces = decl.derivedInterfaces
				.filter!(i => !!i)
				.map!((i) {
					if (i.typeDecl && !cast(InterfaceDeclaration)i.typeDecl) {
						Type tp = i;
						tp.typeDecl = null;
						return CachedType(tp);
					} else return i;
				})
				.array;
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
                RollbackAllocator rba;
		auto dmod = dparse.parseModule(tokens, filename, &rba);

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

	Declaration[] parseDeclList(const(dparse.Declaration)[] decls, Entity parent)
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

	Declaration[] parseDecl(in dparse.Declaration decl, Entity parent, const(dparse.Attribute)[] additional_attribs = null)
	{
		if (auto ad = decl.attributeDeclaration) {
			additional_attribs ~= decl.attributes;
			additional_attribs ~= ad.attribute;
			return decl.declarations.map!(d => parseDecl(d, parent, additional_attribs)).join();
		}

		if (decl.declarations.length) {
			additional_attribs ~= decl.attributes;
			return decl.declarations.map!(d => parseDecl(d, parent, additional_attribs)).join();
		}

		Declaration[] ret;
		string comment;
		size_t line;
		if (auto fd = decl.functionDeclaration) {
			comment = fd.comment.undecorateComment();
			line = fd.name.line;

			auto fdr = new FunctionDeclaration(parent, fd.name.text.idup);
			fdr.returnType = parseType(fd.returnType, parent);
			fdr.parameters = parseParameters(fd.parameters, fdr);
			Type ft;
			ft.kind = TypeKind.Function;
			//ft.attributes = ...; // TODO!
			//ft.modifiers = ...; // TODO!
			ft.returnType = fdr.returnType;
			ft.parameterTypes = fdr.parameters.map!(p => cast(immutable)p.type).array;
			fdr.type = ft;
			addAttributes(fdr, fd.attributes);
			addTemplateInfo(fdr, fd);

			ret ~= fdr;
		} else if (auto vd = decl.variableDeclaration) {
			comment = vd.comment.undecorateComment();
			line = vd.declarators[0].name.line;
			auto tp = CachedType(parseType(vd.type, parent));
			foreach (d; vd.declarators) {
				auto v = new VariableDeclaration(parent, d.name.text.idup);
				v.type = tp;
				if (d.initializer) v.initializer = new Value(tp, formatNode(d.initializer));
				ret ~= v;
			}
		} else if (auto at = decl.aliasThisDeclaration) {
			// TODO comment?
			line = at.identifier.line;
			auto adr = new AliasDeclaration(parent, "this");
			adr.targetString = at.identifier.text.idup;
			ret ~= adr;
		} else if (auto sd = decl.structDeclaration) {
			comment = sd.comment.undecorateComment();
			line = sd.name.line;
			auto sdr = new StructDeclaration(parent, sd.name.text.idup);
			sdr.members = parseDeclList(sd.structBody.declarations, sdr);
			addTemplateInfo(sdr, sd);
			ret ~= sdr;
			insertIntoTypeMap(sdr);
		} else if (auto cd = decl.classDeclaration) {
			comment = cd.comment.undecorateComment();
			line = cd.name.line;
			auto cdr = new ClassDeclaration(parent, cd.name.text.idup);
			if (cd.baseClassList) foreach (bc; cd.baseClassList.items) {
				Type t;
				t.kind = TypeKind.Primitive;
				t.typeName = formatNode(bc);
				auto ct = CachedType(t);
				cdr.derivedInterfaces ~= ct;
				addPrimType(ct, parent);
			}
			cdr.members = parseDeclList(cd.structBody.declarations, cdr);
			addTemplateInfo(cdr, cd);
			ret ~= cdr;
			insertIntoTypeMap(cdr);
		} else if (auto id = decl.interfaceDeclaration) {
			comment = id.comment.undecorateComment();
			line = id.name.line;
			auto idr = new InterfaceDeclaration(parent, id.name.text.idup);
			if (id.baseClassList) foreach (bc; id.baseClassList.items) {
				Type t;
				t.kind = TypeKind.Primitive;
				t.typeName = formatNode(bc);
				CachedType ct = t;
				idr.derivedInterfaces ~= ct;
				addPrimType(ct, parent);
			}
			idr.members = parseDeclList(id.structBody.declarations, idr);
			addTemplateInfo(idr, id);
			ret ~= idr;
			insertIntoTypeMap(idr);
		} else if (auto ud = decl.unionDeclaration) {
			comment = ud.comment.undecorateComment();
			line = ud.name.line;
			auto udr = new UnionDeclaration(parent, ud.name.text.idup);
			udr.members = parseDeclList(ud.structBody.declarations, udr);
			addTemplateInfo(udr, ud);
			ret ~= udr;
			insertIntoTypeMap(udr);
		} else if (auto ed = decl.enumDeclaration) {
			logInfo("TODO: enum %s.%s", parent.qualifiedName, ed.name.text);
			// TODO
			return null;
		} else if (auto ad = decl.aliasDeclaration) {
			comment = ad.comment.undecorateComment();
			assert(ad.initializers.length);
			line = ad.initializers[0].name.line;
			foreach (ai; ad.initializers) {
				auto adr = new AliasDeclaration(parent, ai.name.text.idup);
				adr.targetType = parseType(ai.type, parent);
				adr.targetString = formatNode(ai.type);
				ret ~= adr;
			}
		} else if (auto td = decl.templateDeclaration) {
			logInfo("TODO: template %s.%s", parent.qualifiedName, td.name.text);
			// TODO
			return null;
		} else if (auto cd = decl.constructor) {
			comment = cd.comment.undecorateComment();
			line = cd.line;

			auto cdr = new FunctionDeclaration(parent, "this");
			cdr.parameters = parseParameters(cd.parameters, cdr);

			Type t;
			t.kind = TypeKind.Function;
			t.parameterTypes = cdr.parameters.map!(p => p.type).array.assumeUnique;
			cdr.type = t;
			//addAttributes(cdr, cd.memberFunctionAttributes); // TODO!
			addTemplateInfo(cdr, cd);
			ret ~= cdr;
		} else if (auto dd = decl.destructor) {
			// destructors don't get documented for now
			return null;
		} else if (auto scd = decl.staticConstructor) {
			logInfo("TODO: %s.static this()", parent.qualifiedName);
			// TODO
			return null;
		} else if (auto sdd = decl.staticDestructor) {
			logInfo("TODO: %s.static ~this()", parent.qualifiedName);
			// TODO
			return null;
		} else if (auto pbd = decl.postblit) {
			// postblit doesn't get documented for now
			return null;
		} else if (auto id = decl.importDeclaration) {
			// TODO: use for type resolution
			return null;
		} else if (auto id = decl.unittest_) {
			// TODO: use for unit test examples!
			logInfo("TODO: %s.unittest", parent.qualifiedName);
			return null;
		} else {
			logInfo("Unknown declaration in %s: %s", parent.qualifiedName, formatNode(decl));
			return null;
		}

		if (!ret) return null;

		foreach (d; ret) {
			addAttributes(d, additional_attribs);
			addAttributes(d, decl.attributes);

			d.docGroup = new DocGroup(d, comment);
			d.line = line.to!int;
		}

		return ret;
	}

	void addAttributes(Declaration decl, const(dparse.Attribute)[] attrs)
	{
		return addAttributes(decl, attrs.map!(att => formatNode(att)).array);
	}

	void addAttributes(Declaration decl, string[] attrs)
	{
		foreach (as; attrs) {
			switch (as) {
				default:
					if (!decl.attributes.canFind(as))
						decl.attributes ~= CachedString(as);
					break;
				case "private": decl.protection = Protection.Private; break;
				case "package": decl.protection = Protection.Package; break;
				case "protected": decl.protection = Protection.Protected; break;
				case "public": decl.protection = Protection.Public; break;
			}
		}
	}

	VariableDeclaration[] parseParameters(in dparse.Parameters dparams, FunctionDeclaration parent)
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

	VariableDeclaration parseParameter(in dparse.Parameter dparam, FunctionDeclaration parent)
	{
		auto ret = new VariableDeclaration(parent, dparam.name.text.idup);
		ret.type = parseType(dparam.type, parent);
		if (dparam.default_) {
			ret.initializer = new Value;
			ret.initializer.type = ret.type;
			ret.initializer.valueString = formatNode(dparam.default_);
		}
		addAttributes(ret, dparam.parameterAttributes.map!(a => dlex.str(a)).array);
		return ret;
	}

	Type parseType(in dparse.Type type, Entity scope_)
	{
		auto ret = parseType(type.type2, scope_);
		foreach (tc; type.typeConstructors)
			ret.modifiers ~= CachedString(dlex.str(tc));

		foreach (sf; type.typeSuffixes) {
			if (sf.delegateOrFunction.text) {
				if (sf.delegateOrFunction.text == "function")
					ret = Type.makeFunction(CachedType(ret), parseParameters(sf.parameters, null).map!(p => p.type).array.assumeUnique);
				else ret = Type.makeDelegate(CachedType(ret), parseParameters(sf.parameters, null).map!(p => p.type).array.assumeUnique);
			}
			else if (sf.star.type != dlex.tok!"") ret = Type.makePointer(CachedType(ret));
			else if (sf.array) {
				if (sf.type) ret = ret.makeAssociativeArray(CachedType(ret), CachedType(parseType(sf.type, scope_)));
				else if (sf.low) ret = ret.makeStaticArray(CachedType(ret), formatNode(sf.low));
				else ret = Type.makeArray(CachedType(ret));
			}
		}

		ret.text = formatNode(type);
		return ret;
	}

	Type parseType(in dparse.Type2 type, Entity scope_)
	{
		Type ret;
		if (type.builtinType) {
			ret.kind = TypeKind.Primitive;
			ret.typeName = dlex.str(type.builtinType);
		} else if (type.symbol) {
			ret.kind = TypeKind.Primitive;
			ret.typeName = formatNode(type.symbol);
			addPrimType(CachedType(ret), scope_);
		} else if (auto te = type.typeofExpression) {
			ret.kind = TypeKind.Primitive;
			ret.typeName = formatNode(te.expression);
			// te.return_?
		} else if (auto itc = type.identifierOrTemplateChain) {
			ret.kind = TypeKind.Primitive;
			ret.typeName = itc.identifiersOrTemplateInstances
				.map!(it => it.templateInstance ? formatNode(it.templateInstance) : it.identifier.text.idup)
				.join(".");
			addPrimType(CachedType(ret), scope_);
		} else if (auto tc = type.typeConstructor) {
			ret = parseType(type.type, scope_);
			ret.modifiers = CachedString(dlex.str(tc)) ~ ret.modifiers;
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

	private void addPrimType(CachedType tp, const(Entity) decl)
	{
		m_primTypes ~= tuple(tp, Rebindable!(const(Entity))(decl));
	}
}


private string undecorateComment(string str)
{
	if (!str.length) return "";

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

private void addTemplateInfo(T)(Declaration decl, T ddecl)
{
	if (ddecl.templateParameters) {
		decl.isTemplate = true;
		if (auto tpl = ddecl.templateParameters.templateParameterList)
			decl.templateArgs = tpl.items.map!(tp => new TemplateParameterDeclaration(decl, formatNode(tp))).array;
		if (ddecl.constraint)
			decl.templateConstraint = formatNode(ddecl.constraint.expression);
	}
}
