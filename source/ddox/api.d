/**
	Internal functions for use inside the HTML templates.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.api;

public import ddox.ddox;
public import ddox.ddoc;

import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.string;
import vibe.core.log;
import vibe.data.json;



class DocGroupContext : DdocContext {
	private {
		DocGroup m_group;
		string delegate(Entity ent) m_linkTo;
		string[string] m_inheritedMacros;
	}

	this(DocGroup grp, string delegate(Entity ent) link_to)
	{
		m_group = grp;
		m_linkTo = link_to;

		// inherit macros of parent scopes
		if (grp.members.length > 0) {
			auto e = grp.members[0];
			while (true) {
				if (cast(Module)e) break;
				e = e.parent;
				if (!e) break;

				//auto comment = e.docGroup.comment; // TODO: make this work!
				auto comment = new DdocComment(e.docGroup.text);
				foreach (k, v; comment.macros)
					if (k !in m_inheritedMacros)
						m_inheritedMacros[k] = v;
			}
		}
	}

	@property string docText() { return m_group.text; }
	@property string[string] overrideMacroDefinitions() { return null; }
	@property string[string] defaultMacroDefinitions() { return m_inheritedMacros; }

	string lookupScopeSymbolLink(string name)
	{
		if (name == "this") return null;

		bool is_global = false;
		if (name.startsWith(".")) {
			is_global = true;
			name = name[1 .. $];
		}
		
		foreach( def; m_group.members ){
			Entity n, nmod;
			if (is_global) {
				n = def.module_.lookup(name);
				nmod = def.module_.lookup!Module(name);
			} else {
				// if this is a function, first search the parameters
				// TODO: maybe do the same for function/delegate variables/type aliases
				if( auto fn = cast(FunctionDeclaration)def ){
					foreach( p; fn.parameters )
						if( p.name == name )
							return m_linkTo(p);
				}

				// then look up the name in the outer scope
				n = def.lookup(name);
				nmod = def.lookup!Module(name);
			}

			// packages are not linked
			if (cast(Package)n) {
				if (nmod) n = nmod;
				else continue;
			}

			// module names must be fully qualified
			if( auto mod = cast(Module)n )
				if( mod.qualifiedName != name )
					continue;

			// don't return links to the declaration itself, but
			// the sepcial string # that will still print the identifier
			// as code
			if( n is def ) return "#";
			
			if( n ) return m_linkTo(n);
		}
		return null;
	}
}


///
string getFunctionName(Json proto)
{
	auto n = proto.name.get!string;
	if( auto ptn = "templateName" in proto ){
		auto tn = ptn.get!string;
		if( tn.startsWith(n~"(") )
			return tn;
		return tn ~ "." ~ n;
	}
	return n;
}

///
unittest {
	assert(getFunctionName(Json(["name": Json("test")])) == "test");
}

DocGroup[] docGroups(Declaration[] items)
{
	DocGroup[] ret;
	foreach( itm; items ){
		bool found = false;
		foreach( g; ret )
			if( g is itm.docGroup ){
				found = true;
				break;
			}
		if( !found ) ret ~= itm.docGroup;
	}
	return ret;
}


bool hasChild(T)(Module mod){ return hasChild!T(mod.members); }
bool hasChild(T)(CompositeTypeDeclaration decl){ return hasChild!T(decl.members); }
bool hasChild(T)(TemplateDeclaration mod){ return hasChild!T(mod.members); }
bool hasChild(T)(Declaration[] decls){ foreach( m; decls ) if( cast(T)m ) return true; return false; }

T[] getChildren(T)(Module mod){ return getChildren!T(mod.members); }
T[] getChildren(T)(CompositeTypeDeclaration decl){ return getChildren!T(decl.members); }
T[] getChildren(T)(TemplateDeclaration decl){ return getChildren!T(decl.members); }
T[] getChildren(T)(Declaration[] decls)
{
	T[] ret;
	foreach( ch; decls )
		if( auto ct = cast(T)ch )
			ret ~= ct;
	return ret;
}

T[] getDocGroups(T)(Module mod){ return getDocGroups!T(mod.members); }
T[] getDocGroups(T)(CompositeTypeDeclaration decl){ return getDocGroups!T(decl.members); }
T[] getDocGroups(T)(TemplateDeclaration decl){ return getDocGroups!T(decl.members); }
T[] getDocGroups(T)(Declaration[] decls)
{
	T[] ret;
	DocGroup dg;
	string name;
	foreach( d; decls ){
		auto dt = cast(T)d;
		if( !dt ) continue;
		if( dt.docGroup !is dg || dt.name != name ){
			ret ~= dt;
			dg = d.docGroup;
			name = d.name;
		}
	}
	return ret;
}

///
string getAttributeString(string[] attributes, AttributeStringKind kind)
{
	enum backAttributes = ["const", "immutable", "shared", "nothrow", "@safe", "@trusted", "@system", "pure", "@property", "@nogc"];
	auto ret = appender!string();
	foreach (a; attributes) {
		bool back = backAttributes.canFind(a);
		if (kind == AttributeStringKind.normal || back == (kind == AttributeStringKind.functionSuffix)) {
			if (kind == AttributeStringKind.functionSuffix) ret.put(' ');
			ret.put(a);
			if (kind != AttributeStringKind.functionSuffix) ret.put(' ');
		}
	}
	return ret.data;
}
/// ditto
string getAttributeString(Declaration decl, AttributeStringKind kind)
{
	return getAttributeString(decl.attributes, kind);
}

enum AttributeStringKind { normal, functionPrefix, functionSuffix }

string[] declStyleClasses(Declaration decl)
{
	string[] ret;
	ret ~= decl.protection.to!string().toLower();
	if (decl.inheritingDecl) ret ~= "inherited";
	if (auto tdecl = cast(TypedDeclaration)decl) {
		assert(tdecl.type !is null, typeid(tdecl).name~" declaration without type!?");
		if (tdecl.type.attributes.canFind("@property")) ret ~= "property";
		if (tdecl.type.attributes.canFind("static")) ret ~= "static";
	}
	return ret;
}

string formatType()(Type type, string delegate(Entity) link_to, bool include_code_tags = true)
{
	if( !type ) return "{null}";
	//logDebug("format type: %s", type);
	auto ret = appender!string();
	formatType(ret, type, link_to, include_code_tags);
	return ret.data();
}

void formatType(R)(ref R dst, Type type, string delegate(Entity) link_to, bool include_code_tags = true)
{
	import ddox.highlight;

	if (include_code_tags) dst.put("<code class=\"prettyprint lang-d\">");
	foreach( att; type.attributes){
		dst.highlightDCode(att);
		dst.put(' ');
	}
	if( type.kind != TypeKind.Function && type.kind != TypeKind.Delegate ){
		foreach( att; type.modifiers ){
			dst.highlightDCode(att);
			dst.highlightDCode("(");
		}
	}
	switch (type.kind) {
		default:
		case TypeKind.Primitive:
			if (type.typeDecl && !cast(TemplateParameterDeclaration)type.typeDecl) {
				auto mn = type.typeDecl.module_.qualifiedName;
				auto qn = type.typeDecl.nestedName;
				if( qn.startsWith(mn~".") ) qn = qn[mn.length+1 .. $];
				formattedWrite(dst, "<a href=\"%s\">%s</a>", link_to(type.typeDecl), highlightDCode(qn).replace(".", ".<wbr/>")); // TODO: avoid allocating replace
			} else {
				dst.highlightDCode(type.typeName);
			}
			if( type.templateArgs.length ){
				dst.put('!');
				dst.put(type.templateArgs);
			}
			break;
		case TypeKind.Function:
		case TypeKind.Delegate:
			formatType(dst, type.returnType, link_to, false);
			dst.put(' ');
			dst.highlightDCode(type.kind == TypeKind.Function ? "function" : "delegate");
			dst.highlightDCode("(");
			foreach( size_t i, pt; type.parameterTypes ){
				if( i > 0 ) dst.highlightDCode(", ");
				formatType(dst, pt, link_to, false);
				if( type._parameterNames[i].length ){
					dst.put(' ');
					dst.put(type._parameterNames[i]);
				}
				if( type._parameterDefaultValues[i] ){
					dst.highlightDCode(" = ");
					dst.put(type._parameterDefaultValues[i].valueString);
				}
			}
			dst.highlightDCode(")");
			foreach( att; type.modifiers ){
				dst.put(' ');
				dst.put(att);
			}
			break;
		case TypeKind.Pointer:
			formatType(dst, type.elementType, link_to, false);
			dst.highlightDCode("*");
			break;
		case TypeKind.Array:
			formatType(dst, type.elementType, link_to, false);
			dst.highlightDCode("[]");
			break;
		case TypeKind.StaticArray:
			formatType(dst, type.elementType, link_to, false);
			dst.highlightDCode("[");
			dst.highlightDCode(type.arrayLength.to!string);
			dst.highlightDCode("]");
			break;
		case TypeKind.AssociativeArray:
			formatType(dst, type.elementType, link_to, false);
			dst.highlightDCode("[");
			formatType(dst, type.keyType, link_to, false);
			dst.highlightDCode("]");
			break;
	}
	if( type.kind != TypeKind.Function && type.kind != TypeKind.Delegate ){
		foreach( att; type.modifiers ) dst.highlightDCode(")");
	}
	if (include_code_tags) dst.put("</code>");
}

Type getPropertyType(Entity[] mems...)
{
	foreach (ov; mems) {
		auto ovf = cast(FunctionDeclaration)ov;
		if (!ovf) continue;
		auto rt = ovf.returnType;
		if (rt.typeName != "void") return rt;
		if (ovf.parameters.length == 0) continue;
		return ovf.parameters[0].type;
	}
	return null;
}

bool anyPropertyGetter(Entity[] mems...)
{
	foreach (ov; mems) {
		auto ovf = cast(FunctionDeclaration)ov;
		if (!ovf) continue;
		if (ovf.returnType.typeName == "void") continue;
		if (ovf.parameters.length == 0) return true;
	}
	return false;
}

bool anyPropertySetter(Entity[] mems...)
{
	foreach (ov; mems) {
		auto ovf = cast(FunctionDeclaration)ov;
		if (!ovf) continue;
		if (ovf.parameters.length == 1) return true;
	}
	return false;
}