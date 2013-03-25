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
	}

	this(DocGroup grp, string delegate(Entity ent) link_to)
	{
		m_group = grp;
		m_linkTo = link_to;
	}

	@property string docText() { return m_group.text; }
	@property string[] overrideMacroDefinitions() { return null; }
	@property string[] defaultMacroDefinitions() { return null; }
	string lookupScopeSymbolLink(string name)
	{
		foreach( def; m_group.members ){
			// if this is a function, first search the parameters
			// TODO: maybe do the same for function/delegate variables/type aliases
			if( auto fn = cast(FunctionDeclaration)def ){
				foreach( p; fn.parameters )
					if( p.name == name )
						return m_linkTo(p);
			}

			// then look up the name in the outer scope
			auto n = def.lookup(name);

			// packages are not linked
			if( cast(Package)n ) continue;

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

string[] declStyleClasses(Declaration decl)
{
	string[] ret;
	ret ~= decl.protection.to!string().toLower();
	if (decl.inheritingDecl) ret ~= "inherited";
	if (auto tdecl = cast(TypedDeclaration)decl) {
		if (tdecl.type.attributes.canFind("@property")) ret ~= "property";
		if (tdecl.type.attributes.canFind("static")) ret ~= "static";
	}
	return ret;
}

string formatType()(Type type, string delegate(Entity) link_to)
{
	if( !type ) return "{null}";
	//logDebug("format type: %s", type);
	auto ret = appender!string();
	formatType(ret, type, link_to);
	return ret.data();
}

void formatType(R)(ref R dst, Type type, string delegate(Entity) link_to)
{
	foreach( att; type.attributes){
		dst.put(att); 
		dst.put(' ');
	}
	if( type.kind != TypeKind.Function && type.kind != TypeKind.Delegate ){
		foreach( att; type.modifiers ){
			dst.put(att);
			dst.put('(');
		}
	}
	switch( type.kind ){
		default:
		case TypeKind.Primitive:
			if( type.typeDecl ){
				auto mn = type.typeDecl.module_.qualifiedName;
				auto qn = type.typeDecl.nestedName;
				if( qn.startsWith(mn~".") ) qn = qn[mn.length+1 .. $];
				formattedWrite(dst, "<a href=\"%s\">%s</a>", link_to(type.typeDecl), qn);
			} else {
				dst.put(type.typeName);
			}
			if( type.templateArgs.length ){
				dst.put('!');
				dst.put(type.templateArgs);
			}
			break;
		case TypeKind.Function:
		case TypeKind.Delegate:
			formatType(dst, type.returnType, link_to);
			dst.put(' ');
			dst.put(type.kind == TypeKind.Function ? "function" : "delegate");
			dst.put('(');
			foreach( size_t i, pt; type.parameterTypes ){
				if( i > 0 ) dst.put(", ");
				formatType(dst, pt, link_to);
				if( type._parameterNames[i].length ){
					dst.put(' ');
					dst.put(type._parameterNames[i]);
				}
				if( type._parameterDefaultValues[i] ){
					dst.put(" = ");
					dst.put(type._parameterDefaultValues[i].valueString);
				}
			}
			dst.put(')');
			foreach( att; type.modifiers ){
				dst.put(' ');
				dst.put(att);
			}
			break;
		case TypeKind.Pointer:
			formatType(dst, type.elementType, link_to);
			dst.put('*');
			break;
		case TypeKind.Array:
			formatType(dst, type.elementType, link_to);
			dst.put("[]");
			break;
		case TypeKind.StaticArray:
			formatType(dst, type.elementType, link_to);
			formattedWrite(dst, "[%s]", type.arrayLength);
			break;
		case TypeKind.AssociativeArray:
			formatType(dst, type.elementType, link_to);
			dst.put('[');
			formatType(dst, type.keyType, link_to);
			dst.put(']');
			break;
	}
	if( type.kind != TypeKind.Function && type.kind != TypeKind.Delegate ){
		foreach( att; type.modifiers ) dst.put(')');
	}
}