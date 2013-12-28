/**
	Parses DMD JSON output and builds up a documentation syntax tree (JSON format from DMD 2.063.2).

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.jsonparser;

import ddox.ddox;
import ddox.entities;

import std.algorithm;
import std.conv;
import ddox.internal.demangle; // std.demangle
import std.exception;
import std.range;
import std.stdio;
import std.string;
import std.typecons;
import vibe.core.log;
import vibe.data.json;


Package parseJsonDocs(Json json, Package root = null)
{
	if( !root ) root = new Package(null, null);
	Parser p;
	foreach( mod; json ){
		p.parseModule(mod, root);
	}
	p.resolveTypes(root);
	return root;
}

private struct Parser
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
			if( decl.baseClass && decl.baseClass.typeDecl && !cast(ClassDeclaration)decl.baseClass.typeDecl )
				decl.baseClass = null;
			foreach( i; decl.derivedInterfaces )
				if( i.typeDecl && !cast(InterfaceDeclaration)i.typeDecl )
					i.typeDecl = null;
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

	void parseModule(Json json, Package root_package)
	{
		Module mod;
		if( "name" !in json ){
			logError("No name attribute in module %s - ignoring", json.filename.opt!string);
			return;
		}
		auto path = json.name.get!string.split(".");
		Package p = root_package;
		foreach( i, pe; path ){
			if( i+1 < path.length ) p = p.getOrAddPackage(pe);
			else mod = p.createModule(pe);
		}

		mod.file = json.file.get!string;
		mod.docGroup = new DocGroup(mod, json.comment.opt!string());
		mod.members = parseDeclList(json.members, mod);
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
		if( json.name.get!string().canFind('(') ){
			ret = parseTemplateDecl(json, parent);
		} else {
			switch( json.kind.get!string ){
				default: enforce(false, "Unknown declaration kind: "~json.kind.get!string); assert(false);
				case "mixin":
				case "import":
				case "static import":
					// TODO: use for symbol resolving
					return null;
				case "destructor": return null;
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

		ret.protection = parseProtection(json.protection);
		ret.line = json["line"].opt!int;
		ret.docGroup = new DocGroup(ret, json.comment.opt!string());

		return ret;
	}

	auto parseAliasDecl(Json json, Entity parent)
	{
		auto ret = new AliasDeclaration(parent, json.name.get!string);
		ret.targetType = parseType(json, ret, null);
		if( ret.targetType && ret.targetType.kind == TypeKind.Primitive && ret.targetType.typeName.length == 0 )
			ret.targetType = null;
		insertIntoTypeMap(ret);
		return ret;
	}

	auto parseFunctionDecl(Json json, Entity parent)
	{
		auto ret = new FunctionDeclaration(parent, json.name.opt!string);
		ret.type = parseType(json, ret, "void()");
		// TODO: use "storageClass" and "parameters" fields
		if( ret.type.kind == TypeKind.Function ){
			ret.returnType = ret.type.returnType;
			ret.attributes = ret.type.attributes ~ ret.type.modifiers;
			if (auto psc = "storageClass" in json)
				foreach (sc; *psc)
					if (!ret.attributes.canFind(sc.get!string))
						ret.attributes ~= sc.get!string;
			auto params = json.parameters.opt!(Json[]);
			foreach (i, pt; ret.type.parameterTypes) {
				auto pname = ret.type._parameterNames[i];
				auto pdefval = ret.type._parameterDefaultValues[i];
				if (i < params.length && params[i].name.type == Json.Type.String)
					pname = params[i].name.get!string();
				auto decl = new VariableDeclaration(ret, pname);
				decl.type = pt;
				decl.initializer = pdefval;
				ret.parameters ~= decl;
			}
			foreach (size_t i, pn; json.opt!(Json[]))
				ret.parameters[i].name = pn.get!string();
		} else {
			logError("Expected function type for '%s'/'%s', got %s %s", json["type"].opt!string, demangleType(json["deco"].opt!string), ret.type.kind, ret.type.typeName);
		}
		return ret;
	}

	auto parseEnumDecl(Json json, Entity parent)
	{
		auto ret = new EnumDeclaration(parent, json.name.get!string);
		insertIntoTypeMap(ret);
		if( "base" !in json ){ // FIXME: parse deco instead
			if( auto pd = "baseDeco" in json )
				json.base = demanglePrettyType(pd.get!string());
		}
		ret.baseType = parseType(json.base, ret);
		auto mems = parseDeclList(json.members, ret);
		foreach( m; mems ){
			auto em = cast(EnumMemberDeclaration)m;
			assert(em !is null, "Enum containing non-enum-members?");
			ret.members ~= em;
		}
		return ret;
	}

	auto parseEnumMemberDecl(Json json, Entity parent)
	{
		auto ret = new EnumMemberDeclaration(parent, json.name.get!string);
		//ret.value = parseValue(json.value);
		return ret;
	}

	auto parseCompositeDecl(Json json, Entity parent)
	{
		CompositeTypeDeclaration ret;
		switch(json.kind.get!string){
			default:
				logWarn("Invalid composite decl kind: %s", json.kind.get!string);
				return new StructDeclaration(parent, json.name.get!string);
			case "struct":
				ret = new StructDeclaration(parent, json.name.get!string);
				break;
			case "union":
				ret = new UnionDeclaration(parent, json.name.get!string);
				break;
			case "class":
				auto clsdecl = new ClassDeclaration(parent, json.name.get!string);
				if( clsdecl.qualifiedName != "object.Object" )
					clsdecl.baseClass = parseType(json.base, clsdecl, "Object", false);
				foreach( intf; json.interfaces.opt!(Json[]) )
					clsdecl.derivedInterfaces ~= parseType(intf, clsdecl);
				ret = clsdecl;
				break;
			case "interface":
				auto intfdecl = new InterfaceDeclaration(parent, json.name.get!string);
				foreach( intf; json.interfaces.opt!(Json[]) )
					intfdecl.derivedInterfaces ~= parseType(intf, intfdecl);
				ret = intfdecl;
				break;
		}

		insertIntoTypeMap(ret);

		ret.members = parseDeclList(json.members, ret);

		return ret;
	}

	auto parseVariableDecl(Json json, Entity parent)
	{
		auto ret = new VariableDeclaration(parent, json.name.get!string);
		ret.type = parseType(json, ret);
		return ret;
	}

	auto parseTemplateDecl(Json json, Entity parent)
	{
		auto ret = new TemplateDeclaration(parent, json.name.get!string);
		foreach (arg; json.parameters.opt!(Json[])) {
			string argstr;
			switch (arg.kind.get!string) {
				case "value":
					if (auto pt = "type" in arg) argstr = pt.get!string ~ ' ';
					else argstr = demanglePrettyType(arg.deco.get!string) ~ ' ';
					goto default;
				case "alias":
					argstr = "alias ";
					goto default;
				case "tuple":
					argstr ~= arg.name.get!string ~ "...";
					break;
				default:
					argstr ~= arg.name.get!string;
			}
			ret.templateArgs ~= new TemplateParameterDeclaration(ret, argstr);
		}
		ret.members = parseDeclList(json.members, ret);
		return ret;
	}

	Type parseType(Json json, Entity sc, string def_type = "void", bool warn_id_not_exists = true)
	{
		string str;
		if( json.type == Json.Type.Undefined ){
			if (warn_id_not_exists) logWarn("No type found for %s.", sc.qualifiedName);
			str = def_type;
		} else if( json.type == Json.Type.String ) str = json.get!string();
		else if( auto pv = "deco" in json ) str = demanglePrettyType(pv.get!string());
		else if( auto pv = "type" in json ) str = pv.get!string();
		else if( auto pv = "originalType" in json ) str = pv.get!string();

		if( str.length == 0 ) str = def_type;

		if( !str.length ) return null;

		auto tokens = tokenizeDSource(str);
		
		logDebug("parse type '%s'", str);
		try {
			auto type = parseTypeDecl(tokens, sc);
			type.text = str;
			return type;
		} catch( Exception e ){
			logError("Error parsing type '%s': %s", str, e.msg);
			auto type = new Type;
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

	Declaration lookupDecl(string qualified_name, Entity sc)
	{
		while(sc){
			auto ent = cast(Declaration)sc.lookup(qualified_name);
			if( ent ) return ent;
			sc = sc.parent;
		}
		return null;
	}

	Type parseTypeDecl(ref string[] tokens, Entity sc)
	{

		auto ret = parseType(tokens, sc);
		return ret;
	}

	Type parseType(ref string[] tokens, Entity sc)
	{
		string[] attributes;
		auto basic_type = parseBasicType(tokens, sc, attributes);
		basic_type.attributes ~= attributes;
		return basic_type;	
	}

	Type parseBasicType(ref string[] tokens, Entity sc, out string[] attributes)
	{
		static immutable global_attribute_keywords = ["abstract", "auto", "const", "deprecated", "enum",
			"extern", "final", "immutable", "inout", "shared", "nothrow", "override", "pure",
			"__gshared", "scope", "static", "synchronize"];

		static immutable parameter_attribute_keywords = ["auto", "const", "final", "immutable", "in", "inout",
			"lazy", "out", "ref", "scope", "shared"];

		static immutable member_function_attribute_keywords = ["const", "immutable", "inout", "shared", "pure", "nothrow"];
		
			
		if( tokens.length > 0 && tokens[0] == "extern" ){
			enforce(tokens[1] == "(");
			enforce(tokens[3] == ")");
			attributes ~= join(tokens[0 .. 4]);
			tokens = tokens[4 .. $];
		}
		
		immutable string[] attribute_keywords = global_attribute_keywords ~ parameter_attribute_keywords ~ member_function_attribute_keywords;
		/*final switch( sc ){
			case DeclScope.Global: attribute_keywords = global_attribute_keywords; break;
			case DeclScope.Parameter: attribute_keywords = parameter_attribute_keywords; break;
			case DeclScope.Class: attribute_keywords = member_function_attribute_keywords; break;
		}*/

		while( tokens.length > 0 ){
			if( tokens.front == "@" ){
				tokens.popFront();
				attributes ~= "@"~tokens.front;
				tokens.popFront();
			} else if( attribute_keywords.countUntil(tokens[0]) >= 0 && tokens[1] != "(" ){
				attributes ~= tokens.front;
				tokens.popFront();
			} else break;
		}

		Type type;
		static immutable const_modifiers = ["const", "immutable", "shared", "inout"];
		if (tokens.length > 2 && tokens[1] == "(" && const_modifiers.countUntil(tokens[0]) >= 0) {
			auto mod = tokens.front;
			tokens.popFrontN(2);
			string[] subattrs;
			type = parseBasicType(tokens, sc, subattrs);
			type.modifiers ~= mod;
			type.attributes ~= subattrs;
			enforce(!tokens.empty && tokens.front == ")", format("Missing ')' for '%s('", mod));
			tokens.popFront();
		} else {
			type = new Type;
			type.kind = TypeKind.Primitive;
			m_primTypes ~= tuple(type, sc);

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
			if( i == 0 && tokens[0] == "..." ){
				type_name = "...";
				nested_name = null;
			} else if( i == 0 && tokens[0] == "(" ){
				type_name = "constructor";
				nested_name = null;
			} else {
				enforce(i > 0, "Expected identifier but got "~tokens.front);
				type.typeName = join(tokens[start .. end]);
				//type.typeDecl = cast(Declaration)sc.lookup(type.typeName);
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
					
					// HACK: dropping the actual type name here!
					while (!tokens.empty && tokens.front == ".") {
						tokens.popFront();
						if (!tokens.empty()) tokens.popFront();
					}
				}
			}
		}
		
		while( !tokens.empty ){
			if( tokens.front == "*" ){
				auto ptr = new Type;
				ptr.kind = TypeKind.Pointer;
				ptr.elementType = type;
				type = ptr;
				tokens.popFront();
			} else if( tokens.front == "[" ){
				tokens.popFront();
				if( tokens.front == "]" ){
					auto arr = new Type;
					arr.kind = TypeKind.Array;
					arr.elementType = type;
					type = arr;
				} else {
					string[] tokens_copy = tokens;
					Type keytp;
					if (!isDigit(tokens.front[0]) && tokens.front != "!") keytp = parseType(tokens_copy, sc);
					if (keytp && !tokens_copy.empty && tokens_copy.front == "]") {
						tokens = tokens_copy;
						logDebug("GOT TYPE: %s", keytp.toString());
						auto aa = new Type;
						aa.kind = TypeKind.AssociativeArray;
						aa.elementType = type;
						aa.keyType = keytp;
						type = aa;
					} else {
						auto arr = new Type;
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
		
		while (!tokens.empty && (tokens.front == "function" || tokens.front == "delegate" || tokens.front == "(")) {
			Type ftype = new Type;
			ftype.kind = tokens.front == "(" || tokens.front == "function" ? TypeKind.Function : TypeKind.Delegate;
			ftype.returnType = type;
			if (tokens.front != "(") tokens.popFront();
			enforce(tokens.front == "(");
			tokens.popFront();
			if (!tokens.empty && tokens.front == ",") tokens.popFront(); // sometimes demangleType() returns something like "void(, ...)"
			while (true) {
				if (tokens.front == ")") break;
				enforce(!tokens.empty);
				ftype.parameterTypes ~= parseTypeDecl(tokens, sc);
				if (tokens.front != "," && tokens.front != ")") {
					ftype._parameterNames ~= tokens.front;
					tokens.popFront();
				} else ftype._parameterNames ~= null;
				if (tokens.front == "...") {
					ftype._parameterNames[$-1] ~= tokens.front;
					tokens.popFront();
				}
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
					ftype._parameterDefaultValues ~= parseValue(defval);
					logDebug("got defval %s", defval);
				} else ftype._parameterDefaultValues ~= null;
				if (tokens.front == ")") break;
				enforce(tokens.front == ",", "Expecting ',', got "~tokens.front);
				tokens.popFront();
			}
			tokens.popFront();
			type = ftype;
		}

		return type;
	}
	
	string[] tokenizeDSource(string dsource_)
	{
		static immutable dstring[] tokens = [
			"/", "/=", ".", "..", "...", "&", "&=", "&&", "|", "|=", "||",
			"-", "-=", "--", "+", "+=", "++", "<", "<=", "<<", "<<=",
			"<>", "<>=", ">", ">=", ">>=", ">>>=", ">>", ">>>", "!", "!=",
			"!<>", "!<>=", "!<", "!<=", "!>", "!>=", "(", ")", "[", "]",
			"{", "}", "?", ",", ";", ":", "$", "=", "==", "*", "*=",
			"%", "%=", "^", "^=", "~", "~=", "@", "=>", "#"
		];
		static bool[dstring] token_map;
		
		if( !token_map.length ){
			foreach( t; tokens )
				token_map[t] = true;
			token_map.rehash;
		}
		
		dstring dsource = to!dstring(dsource_);
		
		dstring[] ret;
		outer:
		while(true){
			dsource = stripLeft(dsource);
			if( dsource.length == 0 ) break;
			
			// special token?
			foreach_reverse( i; 1 .. min(5, dsource.length+1) )
				if( dsource[0 .. i] in token_map ){
					ret ~= dsource[0 .. i];
					dsource.popFrontN(i);
					continue outer;
				}
			
			// identifier?
			if( dsource[0] == '_' || std.uni.isAlpha(dsource[0]) ){
				size_t i = 1;
				while( i < dsource.length && (dsource[i] == '_' || std.uni.isAlpha(dsource[i]) || isDigit(dsource[i])) ) i++;
				ret ~= dsource[0 .. i];
				dsource.popFrontN(i);
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
				dsource.popFrontN(i+1);
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
				dsource.popFrontN(i+1);
				continue;
			}
			
			// number?
			if( isDigit(dsource[0]) || dsource[0] == '.' ){
				auto dscopy = dsource;
				parse!double(dscopy);
				ret ~= dsource[0 .. dsource.length-dscopy.length];
				dsource.popFrontN(dsource.length-dscopy.length);
				if( dsource.startsWith("u") ) dsource.popFront();
				else if( dsource.startsWith("f") ) dsource.popFront();
				continue;
			}
			
			ret ~= dsource[0 .. 1];
			dsource.popFront();
		}
		
		auto ret_ = new string[ret.length];
		foreach( i; 0 .. ret.length ) ret_[i] = to!string(ret[i]);
		return ret_;
	}

	bool isDigit(dchar ch)
	{
		return ch >= '0' && ch <= '9';
	}

	bool isIdent(string str)
	{
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
		string[] parts = split(decl.qualifiedName, ".");
		foreach( i; 0 .. parts.length ){
			auto partial_name = join(parts[i .. $], ".");
			m_typeMap[partial_name] = decl;
		}
	}
}

string demanglePrettyType(string mangled_type)
{
	auto str = assumeUnique(demangleType(mangled_type));
	str = str.replace("immutable(char)[]", "string");
	str = str.replace("immutable(wchar)[]", "wstring");
	str = str.replace("immutable(dchar)[]", "dstring");
	return str;
}
