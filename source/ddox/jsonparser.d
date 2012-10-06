module ddox.jsonparser;

import ddox.ddox;
import ddox.entities;
import ddox.processors.inherit;
import ddox.processors.sort;

import std.algorithm;
import std.conv;
import std.exception;
import std.range;
import std.stdio;
import std.string;
import std.typecons;
import vibe.core.log;
import vibe.data.json;


Package parseJsonDocs(Json json, DdoxSettings settings, Package root = null)
{
	if( !root ) root = new Package(null, null);
	Parser p;
	foreach( mod; json ){
		p.parseModule(mod, root);
	}
	p.resolveTypes(root);

	if( settings.inheritDocumentation ){
		writefln("Searching for inherited docs...");
		inheritDocs(root);
	}
	if( settings.moduleSort == SortMode.Name ){
		writefln("Sorting docs...");
		sortDocs!((a, b) => a.name < b.name)(root);
	}
	return root;
}

struct Parser
{
	private Tuple!(Type, Entity)[] m_primTypes;
	private Declaration[string] m_typeMap;

	void resolveTypes(Package root)
	{
		bool isTypeDecl(DeclarationKind a)
		{
			switch(a){
				default: return false;
				case DeclarationKind.Struct:
				case DeclarationKind.Class:
				case DeclarationKind.Interface:
				case DeclarationKind.Enum:
					return true;
			}
		}

		foreach( t; m_primTypes ){
			auto decl = cast(Declaration)t[1].lookup(t[0].typeName);
			if( !decl || !isTypeDecl(decl.kind) ){
				auto pd = t[0].typeName in m_typeMap;
				if( pd ) decl = *pd;
			}
			if( decl && isTypeDecl(decl.kind) )
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
		auto path = json.name.get!string.split(".");
		Package p = root_package;
		foreach( i, pe; path ){
			if( i+1 < path.length ) p = p.getOrAddPackage(pe);
			else mod = p.createModule(pe);
		}

		mod.file = json.file.get!string;
		mod.docGroup = new DocGroup(mod, json.comment.opt!string().strip());
		mod.members = parseDeclList(json.members, mod);
	}

	Declaration[] parseDeclList(Json json, Entity parent)
	{
		if( json.type == Json.Type.Undefined ) return null;
		DocGroup lastdoc;
		Declaration[] ret;
		foreach( mem; json ){
			auto decl = parseDecl(mem, parent);
			auto doc = mem.comment.opt!string().strip();
			if( doc == "ditto" && lastdoc ){
				lastdoc.members ~= decl;
				decl.docGroup = lastdoc;
			} else if( doc == "private" ){
				decl.protection = Protection.Private;
				decl.docGroup = new DocGroup(decl, null);
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
				case "alias": ret = parseAliasDecl(json, parent); break;
				case "constructor": ret = parseFunctionDecl(json, parent); break;
				case "function": ret = parseFunctionDecl(json, parent); break;
				case "enum": ret = parseEnumDecl(json, parent); break;
				case "enum member": ret = parseEnumMemberDecl(json, parent); break;
				case "struct": ret = parseCompositeDecl(json, parent); break;
				case "class": ret = parseCompositeDecl(json, parent); break;
				case "interface": ret = parseCompositeDecl(json, parent); break;
				case "variable": ret = parseVariableDecl(json, parent); break;
				case "template": ret = parseTemplateDecl(json, parent); break;
			}
		}

		ret.protection = parseProtection(json.protection);
		ret.line = json.line.get!int;
		ret.docGroup = new DocGroup(ret, json.comment.opt!string().strip());

		return ret;
	}

	auto parseAliasDecl(Json json, Entity parent)
	{
		auto ret = new AliasDeclaration(parent, json.name.get!string);
		insertIntoTypeMap(ret);
		//if( auto pt = "type" in json ) ret.targetType = parseType(*pt, parent);
		return ret;
	}

	auto parseFunctionDecl(Json json, Entity parent)
	{
		auto ret = new FunctionDeclaration(parent, json.name.get!string);
		ret.type = parseType(json["type"], parent);
		ret.returnType = ret.type.returnType;
		ret.attributes = ret.type.attributes;
		assert(ret.type.kind == TypeKind.Function, "Expected function type, got "~to!string(ret.type.kind));
		foreach( i, pt; ret.type.parameterTypes ){
			auto decl = new VariableDeclaration(ret, ret.type._parameterNames[i]);
			decl.type = pt;
			decl.initializer = ret.type._parameterDefaultValues[i];
			ret.parameters ~= decl;
		}
		return ret;
	}

	auto parseEnumDecl(Json json, Entity parent)
	{
		auto ret = new EnumDeclaration(parent, json.name.get!string);
		insertIntoTypeMap(ret);
		ret.baseType = parseType(json.base, parent);
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
			default: assert(false, "Invalid composite decl kind.");
			case "struct":
				ret = new StructDeclaration(parent, json.name.get!string);
				break;
			case "class":
				auto clsdecl = new ClassDeclaration(parent, json.name.get!string);
				clsdecl.baseClass = parseType(json.base, parent, "Object");
				foreach( intf; json.interfaces.opt!(Json[]) )
					clsdecl.derivedInterfaces ~= parseType(intf, parent);
				ret = clsdecl;
				break;
			case "interface":
				auto intfdecl = new InterfaceDeclaration(parent, json.name.get!string);
				foreach( intf; json.interfaces.opt!(Json[]) )
					intfdecl.derivedInterfaces ~= parseType(intf, parent);
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
		ret.type = parseType(json["type"], parent);
		return ret;
	}

	auto parseTemplateDecl(Json json, Entity parent)
	{
		auto name = json.name.get!string().strip();
		auto cidx = name.countUntil('(');
		assert(cidx > 0 && name.endsWith(')'), "Template name must be of the form name(args)");

		auto ret = new TemplateDeclaration(parent, name[0 .. cidx]);
		ret.templateArgs = name[cidx+1 .. $-1];
		ret.members = parseDeclList(json.members, ret);
		return ret;
	}

	Type parseType(Json tp, Entity sc, string def_type = "void")
	{
		auto str = tp.opt!string;
		if( str.length == 0 ) str = def_type;
		auto tokens = tokenizeDSource(str);
		
		logInfo("parse type '%s'", str);
		auto type = parseTypeDecl(tokens, sc);
		type.text = str;
		return type;
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
		static immutable global_attribute_keywords = ["abstract", "auto", "const", "deprecated", "enum",
			"extern", "final", "immutable", "inout", "shared", "nothrow", "override", "pure",
			"__gshared", "scope", "static", "synchronize"];

		static immutable parameter_attribute_keywords = ["auto", "const", "final", "immutable", "in", "inout",
			"lazy", "out", "ref", "scope", "shared"];

		static immutable member_function_attribute_keywords = ["const", "immutable", "inout", "shared", "pure", "nothrow"];
		
			
		string[] attributes;	
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

		auto ret = parseType(tokens, sc);
		ret.attributes = attributes;
		return ret;
	}

	Type parseType(ref string[] tokens, Entity sc)
	{
		auto basic_type = parseBasicType(tokens, sc);
		
		while( tokens.length > 0 && (tokens[0] == "function" || tokens[0] == "delegate" || tokens[0] == "(") ){
			Type ret = new Type;
			ret.kind = tokens.front == "(" || tokens.front == "function" ? TypeKind.Function : TypeKind.Delegate;
			ret.returnType = basic_type;
			if( tokens.front != "(" ) tokens.popFront();
			enforce(tokens.front == "(");
			tokens.popFront();
			while(true){
				if( tokens.front == ")" ) break;
				enforce(!tokens.empty);
				ret.parameterTypes ~= parseTypeDecl(tokens, sc);
				if( tokens.front != "," && tokens.front != ")" ){
					ret._parameterNames ~= tokens.front;
					tokens.popFront();
				} else ret._parameterNames ~= null;
				if( tokens.front == "..." ){
					ret._parameterNames[$-1] ~= tokens.front;
					tokens.popFront();
				}
				if( tokens.front == "=" ){
					tokens.popFront();
					string defval;
					int ccount = 0;
					while( !tokens.empty ){
						if( ccount == 0 && (tokens.front == "," || tokens.front == ")") )
							break;
						if( tokens.front == "(" ) ccount++;
						else if( tokens.front == ")" ) ccount--;
						defval ~= tokens.front;
						tokens.popFront();
					}
					ret._parameterDefaultValues ~= parseValue(defval);
					logDebug("got defval %s", defval);
				} else ret._parameterDefaultValues ~= null;
				if( tokens.front == ")" ) break;
				enforce(tokens.front == ",", "Expecting ',', got "~tokens.front);
				tokens.popFront();
			}
			tokens.popFront();
			basic_type = ret;
		}
		
		return basic_type;	
	}

	Type parseBasicType(ref string[] tokens, Entity sc)
	{
		Type type;
		{
			static immutable const_modifiers = ["const", "immutable", "shared", "inout"];
			string[] modifiers;
			while( tokens.length > 2 ){
				if( tokens[1] == "(" && const_modifiers.countUntil(tokens[0]) >= 0 ){
					modifiers ~= tokens[0];
					tokens.popFrontN(2);
				} else break;
			}
			
			
			if( modifiers.length > 0 ){
				type = parseBasicType(tokens, sc);
				type.modifiers = modifiers;
				foreach( i; 0 .. modifiers.length ){
					//enforce(tokens[i] == ")", "expected ')', got '"~tokens[i]~"'");
					if( tokens[i] == ")" ) // FIXME: this is a hack to make parsing(const(immutable(char)[][]) somehow "work"
						tokens.popFront();
				}
				//tokens.popFrontN(modifiers.length);
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
					type.typeName = join(tokens[start .. end], ".");
					//type.typeDecl = cast(Declaration)sc.lookup(type.typeName);
					tokens.popFrontN(i);

					if( !tokens.empty && tokens.front == "!" ){
						tokens.popFront();
						if( tokens.front == "(" ){
							size_t j = 1;
							while( j < tokens.length && tokens[j] != ")" ) j++;
							type.templateArgs = join(tokens[0 .. j+1]);
							tokens.popFrontN(j+1);
						} else {
							type.templateArgs = tokens[0];
							tokens.popFront();
						}
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
				} else if( isDigit(tokens.front[0]) ){
					auto arr = new Type;
					arr.kind = TypeKind.StaticArray;
					arr.elementType = type;
					arr.arrayLength = to!int(tokens.front);
					tokens.popFront();
					type = arr;
				} else {
					auto keytp = parseType(tokens, sc);
					logDebug("GOT TYPE: %s", keytp.toString());
					auto aa = new Type;
					aa.kind = TypeKind.AssociativeArray;
					aa.elementType = type;
					aa.keyType = keytp;
					type = aa;
				}
				enforce(tokens.front == "]", "Expected '[', got '"~tokens.front~"'.");
				tokens.popFront();
			} else break;
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
				assert(false);
			}
			
			// string? (incomplete!)
			if( dsource[0] == '"' ){
				size_t i = 1;
				while( dsource[i] != '"' ){
					i++;
					enforce(i < dsource.length);
				}
				ret ~= dsource[0 .. i+1];
				dsource.popFrontN(i+1);
				continue;
			}
			
			// number?
			if( isDigit(dsource[0]) || dsource[0] == '.' ){
				assert(isDigit(dsource[0]));
				size_t i = 1;
				while( i < dsource.length && isDigit(dsource[i]) ) i++;
				assert(i >= dsource.length || dsource[i] != '.' && dsource[i] != 'e' && dsource[i] != 'E');
				// only integers supported any badly supported
				ret ~= dsource[0 .. i];
				dsource.popFrontN(i);
				if( dsource.startsWith("u") ) dsource.popFront();
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

