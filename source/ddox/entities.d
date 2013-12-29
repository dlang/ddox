/**
	Contains definitions of the syntax tree elements.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.entities;

import ddox.ddoc;
import std.algorithm : countUntil, joiner, map;
import std.range;
import std.string;
import std.typecons;


class Entity {
	Entity parent;
	string name;
	DocGroup docGroup;

	this(Entity parent, string name)
	{
		this.parent = parent;
		this.name = name;
	}

	@property string qualifiedName()
	const {
		string s = name;
		Rebindable!(const(Entity)) e = parent;
		while( e && e.parent ){
			s = e.name ~ "." ~ s;
			e = e.parent;
		}
		return s;
	}

	@property string moduleName()
	const {
		Rebindable!(const(Entity)) e = this;
		while( e && !cast(Module)e ) e = e.parent;
		if( e ) return e.qualifiedName;
		return null;
	}

	@property string nestedName()
	const {
		string s = name;
		Rebindable!(const(Entity)) e = parent;
		while( e && e.parent ){
			if( cast(Module)e ) break;
			s = e.name ~ "." ~ s;
			e = e.parent;
		}
		return s;
	}

	bool isAncestorOf(in Entity node)
	const {
		auto n = rebindable(node);
		while( n ){
			if( n.parent is this ) return true;
			n = n.parent;
		}
		return false;
	}

	abstract void iterateChildren(bool delegate(Entity) del);

	final T findChild(T = Entity)(string name)
	{
		T ret;
		iterateChildren((ch){ if( ch.name == name ){ ret = cast(T)ch; return ret is null; } return true; });
		return ret;
	}

	final T[] findChildren(T = Entity)(string name)
	{
		T[] ret;
		iterateChildren((ch){ if( ch.name == name ){ auto t = cast(T)ch; if( t ) ret ~= t; } return true; });
		return ret;
	}

	final T lookup(T = Entity)(string qualified_name, bool recurse = true)
	{
		auto parts = split(qualified_name, ".");
		Entity e = this;
		foreach( i, p; parts ){
			if( i+1 < parts.length ){
				e = e.findChild(p);
				if( !e ) break;
			} else {
				auto r = e.findChild!T(p);
				if( r ) return r;
			}
		}
		static if (is(T == Declaration)) {
			if (auto decl = cast(Declaration)this) {
				auto idx = decl.templateArgs.countUntil!(p => p.name == qualified_name);
				if (idx >= 0) return decl.templateArgs[idx];
			}
		}
		if( recurse && parent ) return parent.lookup!T(qualified_name);
		return null;
	}

	final T[] lookupAll(T = Entity)(string qualified_name)
	{
		auto parts = split(qualified_name, ".");
		Entity e = this;
		foreach( i, p; parts ){
			if( i+1 < parts.length ) e = e.findChild(p);
			else return e.findChildren!T(p);
			if( !e ) return null;
		}
		return null;
	}

	final Entity lookdown(string qualified_name, bool stop_at_module_level = false)
	{
		auto parts = split(qualified_name, ".");
		Entity e = this;
		foreach( p; parts ){
			e = e.findChild(p);
			if( !e ){
				if( stop_at_module_level && cast(Module)this ) return null;
				Entity ret;
				iterateChildren((ch){
					if( auto res = (cast()ch).lookdown(qualified_name) ){
						ret = res;
						return false;
					}
					return true; 
				});
				return ret;
			}
		}
		return e;
	}

	void visit(T)(void delegate(T) del)
	{
		if( auto t = cast(T)this ) del(t);
		iterateChildren((ch){ ch.visit!T(del); return true; });
	}
}

final class DocGroup {
	Entity[] members;
	string text;
	DdocComment comment;

	this(Entity entity, string text)
	{
		this.members = [entity];
		this.text = text;
		this.comment = new DdocComment(text);
	}
}

final class Package : Entity {
	Package[] packages;
	Module[] modules;

	this(Entity parent, string name){ super(parent, name); }

	Module createModule(string name)
	{
		assert(findChild!Module(name) is null, "Module already present");
		auto mod = new Module(this, name);
		modules ~= mod;
		return mod;
	}

	Package getOrAddPackage(string name)
	{
		foreach( p; packages )
			if( p.name == name )
				return p;
		auto pack = new Package(this, name);
		pack.docGroup = new DocGroup(pack, null);
		packages ~= pack;
		return pack;
	}

	override void iterateChildren(bool delegate(Entity) del)
	{
		foreach( p; packages ) if( !del(p) ) return;
		foreach( m; modules ) if( !del(m) ) return;
	}
}

final class Module : Entity{
	Declaration[] members;
	string file;

	this(Entity parent, string name){ super(parent, name); }

	override void iterateChildren(bool delegate(Entity) del)
	{
		foreach( m; members ) if( !del(m) ) return;
	}
}

enum DeclarationKind {
	Variable,
	Function,
	Struct,
	Union,
	Class,
	Interface,
	Enum,
	EnumMember,
	Alias,
	Template,
	TemplateParameter
}

enum Protection {
	Private,
	Package,
	Protected,
	Public
}

class Declaration : Entity {
	Declaration inheritingDecl;
	Protection protection = Protection.Public;
	int line;
	bool isTemplate;
	TemplateParameterDeclaration[] templateArgs;

	abstract @property Declaration dup();
	abstract @property DeclarationKind kind();
	@property inout(Declaration) parentDeclaration() inout { return cast(inout(Declaration))parent; }
	@property Module module_() {
		Entity e = parent;
		while(e){
			if( auto m = cast(Module)e ) return m;
			e = e.parent;
		}
		assert(false, "Declaration without module?");
	}
	@property const(Module) module_() const {
		Rebindable!(const(Entity)) e = parent;
		while(e){
			if( auto m = cast(const(Module))e ) return m;
			e = e.parent;
		}
		assert(false, "Declaration without module?");
	}

	@property string templateArgsString() const {
		if (!isTemplate) return null;
		return format("(%s)", (cast(string[])templateArgs.map!(a => a.name).array).join(", "));
	}

	this(Entity parent, string name){ super(parent, name); }

	abstract override void iterateChildren(bool delegate(Entity) del);

	protected void copyFrom(Declaration src)
	{
		this.docGroup = src.docGroup;
		this.inheritingDecl = src.inheritingDecl;
		this.protection = src.protection;
		this.line = src.line;
		this.templateArgs = src.templateArgs;
	}
}

class TypedDeclaration : Declaration {
	Type type;

	abstract override @property DeclarationKind kind() const;

	this(Entity parent, string name){ super(parent, name); }

	abstract override void iterateChildren(bool delegate(Entity) del);

	protected override void copyFrom(Declaration src)
	{
		super.copyFrom(src);
		if (auto tsrc = cast(TypedDeclaration)src)
			this.type = tsrc.type;
	}
}

final class VariableDeclaration : TypedDeclaration {
	Value initializer;

	override @property VariableDeclaration dup() { auto ret = new VariableDeclaration(parent, name); ret.copyFrom(this); ret.initializer = initializer; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Variable; }

	this(Entity parent, string name){ super(parent, name); }

	override void iterateChildren(bool delegate(Entity) del) {}
}

final class FunctionDeclaration : TypedDeclaration {
	Type returnType;
	VariableDeclaration[] parameters;
	string[] attributes;

	override @property FunctionDeclaration dup() { auto ret = new FunctionDeclaration(parent, name); ret.copyFrom(this); ret.returnType = returnType; ret.parameters = parameters.dup; ret.attributes = attributes; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Function; }

	this(Entity parent, string name){ super(parent, name); }

	bool hasAttribute(string att) const { foreach( a; attributes ) if( a == att ) return true; return false; }

	override void iterateChildren(bool delegate(Entity) del)
	{
		foreach( p; parameters ) del(p);
	}
}

class CompositeTypeDeclaration : Declaration {
	Declaration[] members;

	override abstract @property DeclarationKind kind() const;
 
	this(Entity parent, string name){ super(parent, name); }

	override void iterateChildren(bool delegate(Entity) del)
	{
		foreach( m; members ) if( !del(m) ) return;
	}
}

final class StructDeclaration : CompositeTypeDeclaration {
	override @property StructDeclaration dup() { auto ret = new StructDeclaration(parent, name); ret.copyFrom(this); ret.members = members; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Struct; }

	this(Entity parent, string name){ super(parent, name); }
}

final class UnionDeclaration : CompositeTypeDeclaration {
	override @property UnionDeclaration dup() { auto ret = new UnionDeclaration(parent, name); ret.copyFrom(this); ret.members = members; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Union; }

	this(Entity parent, string name){ super(parent, name); }
}

final class InterfaceDeclaration : CompositeTypeDeclaration {
	Type[] derivedInterfaces;

	override @property InterfaceDeclaration dup() { auto ret = new InterfaceDeclaration(parent, name); ret.copyFrom(this); ret.members = members; ret.derivedInterfaces = derivedInterfaces.dup; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Interface; }

	this(Entity parent, string name){ super(parent, name); }
}

final class ClassDeclaration : CompositeTypeDeclaration {
	Type baseClass;
	Type[] derivedInterfaces;

	override @property ClassDeclaration dup() { auto ret = new ClassDeclaration(parent, name); ret.copyFrom(this); ret.members = members; ret.baseClass = baseClass; ret.derivedInterfaces = derivedInterfaces.dup; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Class; }

	this(Entity parent, string name){ super(parent, name); }
}

final class EnumDeclaration : CompositeTypeDeclaration {
	Type baseType;

	override @property EnumDeclaration dup() { auto ret = new EnumDeclaration(parent, name); ret.copyFrom(this); ret.members = members; ret.baseType = baseType; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Enum; }

	this(Entity parent, string name){ super(parent, name); }
}

final class EnumMemberDeclaration : Declaration {
	Value value;

	override @property EnumMemberDeclaration dup() { auto ret = new EnumMemberDeclaration(parent, name); ret.copyFrom(this); ret.value = value; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.EnumMember; }
	@property Type type() { if( !value ) return null; return value.type; }

	this(Entity parent, string name){ super(parent, name); }

	override void iterateChildren(bool delegate(Entity) del) {}
}

final class AliasDeclaration : Declaration {
	string[] attributes;
	Declaration targetDecl;
	Type targetType;

	override @property AliasDeclaration dup() { auto ret = new AliasDeclaration(parent, name); ret.copyFrom(this); ret.targetDecl = targetDecl; ret.targetType = targetType; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Alias; }
	@property Type type() { return targetType; }

	this(Entity parent, string name){ super(parent, name); }

	override void iterateChildren(bool delegate(Entity) del) {}
}

final class TemplateDeclaration : Declaration {
	Declaration[] members;

	override @property TemplateDeclaration dup() { auto ret = new TemplateDeclaration(parent, name); ret.copyFrom(this); ret.members = members.dup; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Template; }

	this(Entity parent, string name){ super(parent, name); isTemplate = true; }

	override void iterateChildren(bool delegate(Entity) del)
	{
		foreach( m; members ) del(m);
	}
}

final class TemplateParameterDeclaration : TypedDeclaration {
	override @property TemplateParameterDeclaration dup() { auto ret = new TemplateParameterDeclaration(parent, name); ret.copyFrom(this); ret.type = type; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.TemplateParameter; }

	this(Entity parent, string name){ super(parent, name); type = new Type(this); }

	override void iterateChildren(bool delegate(Entity) del) {}
}

final class Value {
	Type type;
	string valueString;
}

enum TypeKind {
	Primitive,
	Pointer,
	Array,
	StaticArray,
	AssociativeArray,
	Function,
	Delegate
}

final class Type {
	TypeKind kind;
	string[] attributes;
	string[] modifiers;
	string templateArgs;
	string text; // original text as in DMDs JSON output
	// Primitive
	string typeName;
	Declaration typeDecl;
	// P, A, SA, AA
	Type elementType;
	// SA
	string arrayLength;
	// AA
	Type keyType;
	// Function/Delegate
	Type returnType;
	Type[] parameterTypes;
	string[] _parameterNames;
	Value[] _parameterDefaultValues;

	this() {}
	this(Declaration decl) { kind = TypeKind.Primitive; text = decl.nestedName; typeName = text; typeDecl = decl; }

	override equals_t opEquals(Object other_)
	{
		auto other = cast(Type)other_;
		if( !other ) return false;
		if( kind != other.kind ) return false;
		if( attributes != other.attributes ) return false; // TODO use set comparison instead
		if( modifiers != other.modifiers ) return false; // TODO: use set comparison instead

		final switch( kind ){
			case TypeKind.Primitive: return typeName == other.typeName && typeDecl == other.typeDecl;
			case TypeKind.Pointer: 
			case TypeKind.Array: return elementType == other.elementType;
			case TypeKind.StaticArray: return elementType == other.elementType && arrayLength == other.arrayLength;
			case TypeKind.AssociativeArray: return elementType == other.elementType && keyType == other.keyType;
			case TypeKind.Function:
			case TypeKind.Delegate:
				if( returnType != other.returnType ) return false;
				if( parameterTypes.length != other.parameterTypes.length ) return false;
				foreach( i, p; parameterTypes )
					if( p != other.parameterTypes[i] )
						return false;
		}
		return true;
	}
}
