/**
	Parses DMD JSON output and builds up a documentation syntax tree (JSON format from DMD 2.063.2).

	Copyright: © 2012-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.parsers.jsonparser;

import ddox.ddox;
import ddox.entities;

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


Package parseJsonDocs(Json json, Package root = null)
{
	if( !root ) root = new Package(null, null);
	Parser p;
	foreach (mod; json)
		p.parseModuleDecls(mod, root);
	p.parseTypes();
	return root;
}

private struct Parser
{
	// global map of type declarations with all partially qualified names
	// used to lookup type names for which the regular lookup has failed
	private Declaration[string] m_typeMap;

	Tuple!(Declaration, Json)[] m_declarations;

	void parseModuleDecls(Json json, Package root_package)
	{
		Module mod;
		if( "name" !in json ){
			logError("No name attribute in module %s - ignoring", json["filename"].opt!string);
			return;
		}
		auto path = json["name"].get!string.split(".");
		Package p = root_package;
		foreach (i, pe; path) {
			if( i+1 < path.length ) p = p.getOrAddPackage(pe);
			else mod = p.createModule(pe);
		}

		mod.file = json["file"].get!string;
		mod.docGroup = new DocGroup(mod, json["comment"].opt!string());
		mod.members = parseDeclList(json["members"], mod);
	}

	void parseTypes()
	{
		foreach (d; m_declarations) {
			auto decl = d[0];
			auto json = d[1];
			final switch (decl.kind) {
				case DeclarationKind.Variable: {
						auto v = cast(VariableDeclaration)decl;
						v.type = parseType(json, v);
					} break;
				case DeclarationKind.Function: {
						auto f = cast(FunctionDeclaration)decl;
						f.type = parseType(json, f, "void()");
						if (f.type.kind != TypeKind.Function) {
							logError("Function %s has non-function type: %s", f.qualifiedName, f.type.kind);
							break;
						}
						f.returnType = f.type.returnType;
						f.attributes ~= f.type.attributes ~ f.type.modifiers;

						auto params = json["parameters"].opt!(Json[]);
						if (!params) {
							params.length = f.type.parameterTypes.length;
							foreach (i, pt; f.type.parameterTypes) {
								auto jp = Json.emptyObject;
								jp["name"] = f.type._parameterNames[i];
								jp["type"] = pt.text;
								if (f.type._parameterDefaultValues[i])
									jp["default"] = f.type._parameterDefaultValues[i].valueString;
								params[i] = jp;
							}
						}

						f.parameters.reserve(params.length);
						foreach (i, p; params) {
							auto pname = p["name"].opt!string;
							auto pdecl = new VariableDeclaration(f, pname);
							pdecl.type = parseType(p, f);
							foreach (sc; p["storageClass"].opt!(Json[]))
								if (!pdecl.attributes.canFind(sc.get!string))
									pdecl.attributes ~= CachedString(sc.get!string);
							if (auto pdv = "default" in p)
								pdecl.initializer = parseValue(pdv.opt!string);
							f.parameters ~= pdecl;
						}
					} break;
				case DeclarationKind.Struct: break;
				case DeclarationKind.Union: break;
				case DeclarationKind.Class: {
						auto c = cast(ClassDeclaration)decl;
						if (!c.qualifiedName.equal("object.Object")) {
							c.baseClass = parseType(json["base"], c, "Object", false);
						}
						foreach (intf; json["interfaces"].opt!(Json[]))
							c.derivedInterfaces ~= CachedType(parseType(intf, c));
					} break;
				case DeclarationKind.Interface: {
						auto i = cast(InterfaceDeclaration)decl;
						foreach (intf; json["interfaces"].opt!(Json[]))
							i.derivedInterfaces ~= CachedType(parseType(intf, i));
					} break;
				case DeclarationKind.Enum: {
						auto e = cast(EnumDeclaration)decl;
						e.baseType = parseType(json["base"], e);
					} break;
				case DeclarationKind.EnumMember: break;
				case DeclarationKind.Alias: {
						auto a = cast(AliasDeclaration)decl;
						a.targetType = parseType(json, a, null);
					} break;
				case DeclarationKind.Template: break;
				case DeclarationKind.TemplateParameter:
					auto tp = cast(TemplateParameterDeclaration)decl;
					if (json["kind"] == "value")
						tp.type = parseType(json, tp, null);
					break;
			}
		}
	}

	Declaration[] parseDeclList(Json json, Entity parent)
	{
		if( json.type == Json.Type.Undefined ) return null;
		DocGroup lastdoc;
		Declaration[] ret;
		foreach( mem; json ){
			auto decl = parseDecl(mem, parent);
			if( !decl ) continue;
			auto doc = decl.docGroup;
			if( lastdoc && (doc.text == lastdoc.text && doc.text.length || doc.comment.isDitto) ){
				lastdoc.members ~= decl;
				decl.docGroup = lastdoc;
			} else if( doc.comment.isPrivate ){
				decl.protection = Protection.Private;
				lastdoc = null;
			} else lastdoc = decl.docGroup;
			ret ~= decl;
		}
		return ret;
	}

	Declaration parseDecl(Json json, Entity parent)
	{
		Declaration ret;

		// DMD outputs templates with the wrong kind sometimes
		if (json["name"].get!string().canFind('(') && json["kind"] != "mixin") {
			ret = parseTemplateDecl(json, parent);
		} else {
			switch( json["kind"].get!string ){
				default:
					logWarn("Unknown declaration kind: %s", json["kind"].get!string);
					return null;
				case "generated function": // generated functions are never documented
					return null;
				case "import":
				case "static import":
					// TODO: use for symbol resolving
					return null;
				case "destructor": return null;
				case "mixin": return null;
				case "alias":
					ret = parseAliasDecl(json, parent);
					break;
				case "function":
				case "allocator":
				case "deallocator":
				case "constructor":
					ret = parseFunctionDecl(json, parent);
					break;
				case "enum":
					ret = parseEnumDecl(json, parent);
					break;
				case "enum member":
					ret = parseEnumMemberDecl(json, parent);
					break;
				case "struct":
				case "union":
				case "class":
				case "interface":
					ret = parseCompositeDecl(json, parent);
					break;
				case "variable":
					ret = parseVariableDecl(json, parent);
					break;
				case "template":
					ret = parseTemplateDecl(json, parent);
					break;
			}
		}

		ret.protection = parseProtection(json["protection"]);
		ret.line = json["line"].opt!int;
		ret.docGroup = new DocGroup(ret, json["comment"].opt!string());

		m_declarations ~= tuple(ret, json);

		return ret;
	}

	auto parseAliasDecl(Json json, Entity parent)
	{
		auto ret = new AliasDeclaration(parent, json["name"].get!string);
		ret.attributes = json["storageClass"].opt!(Json[]).map!(j => CachedString(j.get!string)).array.assumeUnique;
		if( ret.targetType && ret.targetType.kind == TypeKind.Primitive && ret.targetType.typeName.length == 0 )
			ret.targetType = CachedType.init;
		insertIntoTypeMap(ret);
		return ret;
	}

	auto parseFunctionDecl(Json json, Entity parent)
	{
		auto ret = new FunctionDeclaration(parent, json["name"].opt!string);
		if (auto psc = "storageClass" in json)
			foreach (sc; *psc)
				if (!ret.attributes.canFind(sc.get!string))
					ret.attributes ~= CachedString(sc.get!string);
		return ret;
	}

	auto parseEnumDecl(Json json, Entity parent)
	{
		auto ret = new EnumDeclaration(parent, json["name"].get!string);
		insertIntoTypeMap(ret);
		if( "base" !in json ){ // FIXME: parse deco instead
			if( auto pd = "baseDeco" in json )
				json["base"] = demanglePrettyType(pd.get!string());
		}
		auto mems = parseDeclList(json["members"], ret);
		foreach( m; mems ){
			auto em = cast(EnumMemberDeclaration)m;
			assert(em !is null, "Enum containing non-enum-members?");
			ret.members ~= em;
		}
		return ret;
	}

	auto parseEnumMemberDecl(Json json, Entity parent)
	{
		auto ret = new EnumMemberDeclaration(parent, json["name"].get!string);
		if (json["value"].opt!string.length)
			ret.value = parseValue(json["value"].opt!string);
		return ret;
	}

	auto parseCompositeDecl(Json json, Entity parent)
	{
		CompositeTypeDeclaration ret;
		switch(json["kind"].get!string){
			default:
				logWarn("Invalid composite decl kind: %s", json["kind"].get!string);
				return new StructDeclaration(parent, json["name"].get!string);
			case "struct":
				ret = new StructDeclaration(parent, json["name"].get!string);
				break;
			case "union":
				ret = new UnionDeclaration(parent, json["name"].get!string);
				break;
			case "class":
				auto clsdecl = new ClassDeclaration(parent, json["name"].get!string);
				ret = clsdecl;
				break;
			case "interface":
				auto intfdecl = new InterfaceDeclaration(parent, json["name"].get!string);
				ret = intfdecl;
				break;
		}

		insertIntoTypeMap(ret);

		ret.members = parseDeclList(json["members"], ret);

		return ret;
	}

	Declaration parseVariableDecl(Json json, Entity parent)
	{
		if (json["storageClass"].opt!(Json[]).canFind!(j => j.opt!string == "enum")) {
			auto ret = new EnumMemberDeclaration(parent, json["name"].get!string);
			if (json["init"].opt!string.length)
				ret.value = parseValue(json["init"].opt!string);
			return ret;
		} else {
			auto ret = new VariableDeclaration(parent, json["name"].get!string);
			if (json["init"].opt!string.length)
				ret.initializer = parseValue(json["init"].opt!string);
			return ret;
		}
	}

	auto parseTemplateDecl(Json json, Entity parent)
	{
		auto ret = new TemplateDeclaration(parent, json["name"].get!string);
		foreach (arg; json["parameters"].opt!(Json[])) {
			string pname = arg["name"].get!string;
			string defvalue = arg["defaultValue"].opt!string;
			string specvalue = arg["specValue"].opt!string;
			bool needs_type_parse = false;

			switch (arg["kind"].get!string) {
				default: break;
				case "value":
					needs_type_parse = true;
					break;
				case "alias":
					pname = "alias " ~ pname;
					break;
				case "tuple":
					pname ~= "...";
					break;
			}

			auto pdecl = new TemplateParameterDeclaration(ret, pname);
			pdecl.defaultValue = defvalue;
			pdecl.specValue = specvalue;
			ret.templateArgs ~= pdecl;
			ret.templateConstraint = json["constraint"].opt!string;

			if (needs_type_parse)
				m_declarations ~= tuple(cast(Declaration)pdecl, arg);
		}
		ret.members = parseDeclList(json["members"], ret);
		return ret;
	}

	Type parseType(Json json, Entity sc, string def_type = "void", bool warn_if_not_exists = true)
		out(ret) { assert(!def_type.length || ret != Type.init); }
	body {
		string str;
		if( json.type == Json.Type.Undefined ){
			if (warn_if_not_exists) logWarn("No type found for %s.", sc.qualifiedName);
			str = def_type;
		} else if (json.type == Json.Type.String) str = json.get!string();
		else if (auto pv = "deco" in json) str = demanglePrettyType(pv.get!string());
		else if (auto pv = "type" in json) str = fixFunctionType(pv.get!string(), def_type);
		else if (auto pv = "originalType" in json) str = fixFunctionType(pv.get!string(), def_type);

		if( str.length == 0 ) str = def_type;

		if( !str.length ) return Type.init;

		return parseType(str, sc);
	}

	Type parseType(string str, Entity sc)
		out(ret) { assert(ret != Type.init); }
	body {
		auto tokens = tokenizeDSource(str);

		logDebug("parse type '%s'", str);
		try {
			auto type = parseTypeDecl(tokens, sc);
			type.text = str;
			return type;
		} catch( Exception e ){
			logError("Error parsing type '%s': %s", str, e.msg);
			Type type;
			type.text = str;
			type.typeName = str;
			type.kind = TypeKind.Primitive;
			return type;
		}
	}

	Value parseValue(string str)
	{
		auto ret = new Value;
		//ret.type = ;
		ret.valueString = str;
		return ret;
	}

	Protection parseProtection(Json prot)
	{
		switch( prot.opt!string ){
			default: return Protection.Public;
			case "package": return Protection.Package;
			case "protected": return Protection.Protected;
			case "private": return Protection.Private;
		}
	}

	Type parseTypeDecl(ref string[] tokens, Entity sc)
	{

		auto ret = parseType(tokens, sc);
		return ret;
	}

	Type parseType(ref string[] tokens, Entity sc)
	{
		CachedString[] attributes;
		auto basic_type = parseBasicType(tokens, sc, attributes);
		basic_type.attributes ~= attributes;
		return basic_type;
	}

	Type parseBasicType(ref string[] tokens, Entity sc, out CachedString[] attributes)
		out(ret) { assert(ret != Type.init); }
	body {
		static immutable global_attribute_keywords = ["abstract", "auto", "const", "deprecated", "enum",
			"extern", "final", "immutable", "inout", "shared", "nothrow", "override", "pure",
			"__gshared", "scope", "static", "synchronize"];

		static immutable parameter_attribute_keywords = ["auto", "const", "final", "immutable", "in", "inout",
			"lazy", "out", "ref", "return", "scope", "shared"];

		static immutable member_function_attribute_keywords = ["const", "immutable", "inout", "ref", "return",
			"scope", "shared", "pure", "nothrow"];


		if( tokens.length > 0 && tokens[0] == "extern" ){
			enforce(tokens[1] == "(");
			enforce(tokens[3] == ")");
			attributes ~= CachedString(join(tokens[0 .. 4]));
			tokens = tokens[4 .. $];
		}

		static immutable string[] attribute_keywords = global_attribute_keywords ~ parameter_attribute_keywords ~ member_function_attribute_keywords;
		/*final switch( sc ){
			case DeclScope.Global: attribute_keywords = global_attribute_keywords; break;
			case DeclScope.Parameter: attribute_keywords = parameter_attribute_keywords; break;
			case DeclScope.Class: attribute_keywords = member_function_attribute_keywords; break;
		}*/

		void parseAttributes(const(string)[] keywords, scope void delegate(CachedString s) del)
		{
			while( tokens.length > 0 ){
				if( tokens.front == "@" ){
					tokens.popFront();
					del(CachedString("@"~tokens.front));
					tokens.popFront();
				} else if( keywords.countUntil(tokens[0]) >= 0 && tokens.length > 1 && tokens[1] != "(" ){
					del(CachedString(tokens.front));
					tokens.popFront();
				} else break;
			}
		}

		parseAttributes(attribute_keywords, (k) { attributes ~= k; });


		Type type;
		static immutable const_modifiers = ["const", "immutable", "shared", "inout"];
		if (tokens.length > 2 && tokens[1] == "(" && const_modifiers.countUntil(tokens[0]) >= 0) {
			auto mod = tokens.front;
			tokens.popFrontN(2);
			CachedString[] subattrs;
			type = parseBasicType(tokens, sc, subattrs);
			type.modifiers ~= CachedString(mod);
			type.attributes ~= subattrs;
			enforce(!tokens.empty && tokens.front == ")", format("Missing ')' for '%s('", mod));
			tokens.popFront();
		} else if (!tokens.empty && !tokens.front.among("function", "delegate")) {
			type.kind = TypeKind.Primitive;

			size_t start = 0, end;
			if( tokens[start] == "." ) start++;
			for( end = start; end < tokens.length && isIdent(tokens[end]); ){
				end++;
				if( end >= tokens.length || tokens[end] != "." )
					break;
				end++;
			}

			size_t i = end;

			string type_name, nested_name;
			if( i == 0 && tokens[0] == "(" ){
				type_name = "constructor";
				nested_name = null;
			} else {
				enforce(i > 0, "Expected identifier but got "~tokens.front);
				auto unqualified_name = tokens[end - 1];
				type.typeName = join(tokens[start .. end]);
				//
				tokens.popFrontN(i);

				if (type.typeName == "typeof" && !tokens.empty && tokens.front == "(") {
					type.typeName ~= "(";
					tokens.popFront();
					int level = 1;
					while (!tokens.empty && level > 0) {
						if (tokens.front == "(") level++;
						else if( tokens.front == ")") level--;
						type.typeName ~= tokens.front;
						tokens.popFront();
					}
				} else if( !tokens.empty && tokens.front == "!" ){
					tokens.popFront();
					if( tokens.front == "(" ){
						size_t j = 1;
						int cc = 1;
						while( cc > 0 ){
							assert(j < tokens.length);
							if( tokens[j] == "(" ) cc++;
							else if( tokens[j] == ")") cc--;
							j++;
						}
						type.templateArgs = join(tokens[0 .. j]);
						tokens.popFrontN(j);
						logDebug("templargs: %s", type.templateArgs);
					} else {
						type.templateArgs = tokens[0];
						tokens.popFront();
					}

					// resolve eponymous template member, e.g. test.Foo!int.Foo
					if (!tokens.empty && tokens.front == ".") {
						tokens.popFront();
						if (!tokens.empty && tokens.front == unqualified_name) { // eponymous template
							resolveTypeDecl(type, sc);
							auto tdecl = cast(TemplateDeclaration)type.typeDecl;
							auto members = tdecl ? tdecl.members : null;
							auto mi = members.countUntil!(m => m.name == tokens.front);
							assert(mi >= 0 || members.empty);
							if (mi >= 0)
								type.typeDecl = members[mi];
							tokens.popFront();
						}
					}
					// HACK: dropping the actual type name here!
					// TODO: resolve other members and adjust typeName,
					// e.g. test.Foo!int.Enum, test.Foo!int.Bar!int, test.Foo!int.Struct.Templ!(int, double)
					while (!tokens.empty && tokens.front == ".") {
 						tokens.popFront();
						if (!tokens.empty()) tokens.popFront();
					}
				}

				resolveTypeDecl(type, sc);
			}
		}

		while( !tokens.empty ){
			if( tokens.front == "*" ){
				Type ptr;
				ptr.kind = TypeKind.Pointer;
				ptr.elementType = type;
				type = ptr;
				tokens.popFront();
			} else if( tokens.front == "[" ){
				tokens.popFront();
				enforce(!tokens.empty, "Missing ']'.");
				if( tokens.front == "]" ){
					Type arr;
					arr.kind = TypeKind.Array;
					arr.elementType = type;
					type = arr;
				} else {
					string[] tokens_copy = tokens;
					Type keytp;
					if (!isDigit(tokens.front[0]) && tokens.front != "!") keytp = parseType(tokens_copy, sc);
					if (keytp != Type.init && !tokens_copy.empty && tokens_copy.front == "]") {
						tokens = tokens_copy;
						Type aa;
						aa.kind = TypeKind.AssociativeArray;
						aa.elementType = type;
						aa.keyType = keytp;
						type = aa;
					} else {
						Type arr;
						arr.kind = TypeKind.StaticArray;
						arr.elementType = type;
						arr.arrayLength = tokens.front;
						tokens.popFront();
						while (!tokens.empty && tokens.front != "]") {
							arr.arrayLength ~= tokens.front;
							tokens.popFront();
						}
						type = arr;
					}
				}
				enforce(tokens.front == "]", "Expected ']', got '"~tokens.front~"'.");
				tokens.popFront();
			} else break;
		}

		if (type == Type.init) {
			type.kind = TypeKind.Primitive;
			type.typeName = "auto";
		}

		while (!tokens.empty && (tokens.front == "function" || tokens.front == "delegate" || tokens.front == "(")) {
			Type ftype;
			ftype.kind = tokens.front == "(" || tokens.front == "function" ? TypeKind.Function : TypeKind.Delegate;
			ftype.returnType = type;
			if (tokens.front != "(") tokens.popFront();
			enforce(tokens.front == "(");
			tokens.popFront();
			// demangleType() returns something like "void(, ...)" for variadic functions or "void(, type)" for typeof(null) parameters
			if (!tokens.empty && tokens.front == ",") tokens.popFront();
			// (...) - D variadic function
			if (tokens.front == "...") {
				ftype.variadic = Type.Variadic.d;
				tokens.popFront();
			}
			while (true) {
				if (tokens.front == ")") break;

				// (int) - parameter type
				enforce(!tokens.empty);
				ftype.parameterTypes ~= CachedType(parseTypeDecl(tokens, sc));


				// (int[]...), (Clazz...) - typesafe variadic function
				if (tokens.front == "...") {
					ftype.variadic = Type.Variadic.typesafe;
					tokens.popFront();
				}
				// (type, ...) - D or extern(C) variadic
				else if (tokens.length > 2 && tokens[0] == "," && tokens[1] == "...") {
					ftype.variadic = Type.Variadic.c; // c and d treated identical for doc-gen
					tokens.popFrontN(2);
				}

				string pname;
				if (tokens.front != "," && tokens.front != ")") {
					pname = tokens.front;
					tokens.popFront();
				}
				ftype._parameterNames ~= CachedString(pname);
				if (tokens.front == "=") {
					tokens.popFront();
					string defval;
					int ccount = 0;
					while (!tokens.empty) {
						if (ccount == 0 && (tokens.front == "," || tokens.front == ")"))
							break;
						if (tokens.front == "(") ccount++;
						else if (tokens.front == ")") ccount--;
						defval ~= tokens.front;
						tokens.popFront();
					}
					ftype._parameterDefaultValues ~= cast(immutable)parseValue(defval);
					logDebug("got defval %s", defval);
				} else ftype._parameterDefaultValues ~= null;
				if (tokens.front == ")") break;
				enforce(tokens.front == ",", "Expecting ',', got "~tokens.front);
				tokens.popFront();
			}
			tokens.popFront();

			parseAttributes(member_function_attribute_keywords, (k) { ftype.attributes ~= cast(immutable)k; });

			type = ftype;
		}

		return type;
	}

	/* special function that looks at the default type to see if a function type
		is expected and if that's the case, fixes up the type string to read
		as a valid D type declaration (DMD omits "function"/"delegate", which
		results in an ambiguous meaning)
	*/
	private string fixFunctionType(string type, string deftype)
	{
		Type dt = parseType(deftype, new Module(null, "dummy"));
		if (deftype == "void()" || dt != Type.init && dt.kind.among(TypeKind.Function, TypeKind.Delegate)) {
			auto last_clamp = type.lastIndexOf(')');
			auto idx = last_clamp-1;
			int l = 1;
			while (idx >= 0) {
				if (type[idx] == ')') l++;
				else if (type[idx] == '(') l--;
				if (l == 0) break;
				idx--;
			}
			if (idx <= 0 || l > 0) return type;
			return type[0 .. idx] ~ " function" ~ type[idx .. $];
		}
		return type;
	}

	string[] tokenizeDSource(string dsource)
	{
		static import std.uni;
		import std.utf : stride;

		static immutable string[] tokens = [
			"/", "/=", ".", "..", "...", "&", "&=", "&&", "|", "|=", "||",
			"-", "-=", "--", "+", "+=", "++", "<", "<=", "<<", "<<=",
			"<>", "<>=", ">", ">=", ">>=", ">>>=", ">>", ">>>", "!", "!=",
			"!<>", "!<>=", "!<", "!<=", "!>", "!>=", "(", ")", "[", "]",
			"{", "}", "?", ",", ";", ":", "$", "=", "==", "*", "*=",
			"%", "%=", "^", "^=", "~", "~=", "@", "=>", "#", "C++"
		];
		static bool[string] token_map;

		if (token_map is null) {
			foreach (t; tokens)
				token_map[t] = true;
			token_map.rehash;
		}

		string[] ret;
		outer:
		while(true){
			dsource = stripLeft(dsource);
			if( dsource.length == 0 ) break;

			// special token?
			foreach_reverse (i; 1 .. min(5, dsource.length+1))
				if (dsource[0 .. i] in token_map) {
					ret ~= dsource[0 .. i];
					dsource = dsource[i .. $];
					continue outer;
				}

			// identifier?
			if( dsource[0] == '_' || std.uni.isAlpha(dsource.front) ){
				size_t i = 1;
				string rem = dsource;
				rem.popFront();
				while (rem.length && (rem[0] == '_' || std.uni.isAlpha(rem.front) || isDigit(rem.front)))
					rem.popFront();
				ret ~= dsource[0 .. $ - rem.length];
				dsource = rem;
				continue;
			}

			// character literal?
			if( dsource[0] == '\'' ){
				size_t i = 1;
				while( dsource[i] != '\'' ){
					if( dsource[i] == '\\' ) i++;
					i++;
					enforce(i < dsource.length);
				}
				ret ~= dsource[0 .. i+1];
				dsource = dsource[i+1 .. $];
				continue;
			}

			// string? (incomplete!)
			if( dsource[0] == '"' ){
				size_t i = 1;
				while( dsource[i] != '"' ){
					if( dsource[i] == '\\' ) i++;
					i++;
					enforce(i < dsource.length);
				}
				ret ~= dsource[0 .. i+1];
				dsource = dsource[i+1 .. $];
				continue;
			}

			// number?
			if( isDigit(dsource[0]) || dsource[0] == '.' ){
				auto dscopy = dsource;
				parse!double(dscopy);
				ret ~= dsource[0 .. dsource.length-dscopy.length];
				dsource = dscopy;
				if (dsource.startsWith("u")) dsource.popFront();
				else if (dsource.startsWith("f")) dsource.popFront();
				continue;
			}

			auto nb = dsource.stride();
			ret ~= dsource[0 .. nb];
			dsource = dsource[nb .. $];
		}

		return ret;
	}

	bool isDigit(dchar ch)
	{
		return ch >= '0' && ch <= '9';
	}

	bool isIdent(string str)
	{
		static import std.uni;

		if( str.length < 1 ) return false;
		foreach( i, dchar ch; str ){
			if( ch == '_' || std.uni.isAlpha(ch) ) continue;
			if( i > 0 && isDigit(ch) ) continue;
			return false;
		}
		return true;
	}

	string fullStrip(string s)
	{
		string chars = " \t\r\n";
		while( s.length > 0 && chars.countUntil(s[0]) >= 0 ) s.popFront();
		while( s.length > 0 && chars.countUntil(s[$-1]) >= 0 ) s.popBack();
		return s;
	}

	void insertIntoTypeMap(Declaration decl)
	{
		auto qname = decl.qualifiedName.to!string;
		m_typeMap[qname] = decl;
		auto idx = qname.indexOf('.');
		while (idx >= 0) {
			qname = qname[idx+1 .. $];
			m_typeMap[qname] = decl;
			idx = qname.indexOf('.');
		}
	}

	private void resolveTypeDecl(ref Type tp, const(Entity) sc)
	{
		if (tp.kind != TypeKind.Primitive) return;
		if (tp.typeDecl) return;

		tp.typeDecl = sc.lookup!Declaration(tp.typeName);
		if (!tp.typeDecl || !isTypeDecl(tp.typeDecl)) tp.typeDecl = m_typeMap.get(tp.typeName, null);
	}

	private bool isTypeDecl(in Declaration a)
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
}

string demanglePrettyType(string mangled_type)
{
	if (mangled_type == "n") return "typeof(null)"; // Workaround D issue 14410
	auto str = assumeUnique(demangleType(mangled_type));
	str = str.replace("immutable(char)[]", "string");
	str = str.replace("immutable(wchar)[]", "wstring");
	str = str.replace("immutable(dchar)[]", "dstring");
	return str;
}
