module ddox.entities;

import std.string;
import std.typecons;


class Entity {
	Entity parent;
	string name;
	DocGroup docGroup;

	@property string qualifiedName() const {
		string s = name;
		Rebindable!(const(Entity)) e = parent;
		while( e && e.parent ){
			s = e.name ~ "." ~ s;
			e = e.parent;
		}
		return s;
	}

	@property string nestedName() const {
		string s = name;
		Rebindable!(const(Entity)) e = parent;
		while( e && e.parent ){
			if( cast(Module)e ) break;
			s = e.name ~ "." ~ s;
			e = e.parent;
		}
		return s;
	}

	this(Entity parent, string name)
	{
		this.parent = parent;
		this.name = name;
	}

	abstract void iterateChildren(bool delegate(inout(Entity)) del) inout;

	final Entity findChild(string name)
	{
		Entity ret;
		iterateChildren((ch){ if( ch.name == name ){ ret = cast()ch; return false; } return true; });
		return ret;
	}
	final const(Entity) findChild(string name)
	const {
		Rebindable!(const(Entity)) ret;
		iterateChildren((ch){ if( ch.name == name ){ ret = cast()ch; return false; } return true; });
		return ret;
	}

	final Entity lookup(string qualified_name)
	{
		auto parts = split(qualified_name, ".");
		Entity e = this;
		foreach( p; parts ){
			e = e.findChild(p);
			if( !e ){
				if( parent ) return parent.lookup(qualified_name);
				else return null;
			}
		}
		return e;
	}
	final const(Entity) lookup(string qualified_name)
	const {
		auto parts = split(qualified_name, ".");
		Rebindable!(const(Entity)) e = this;
		foreach( p; parts ){
			e = e.findChild(p);
			if( !e ) return null;
		}
		return e;
	}

	final Entity lookdown(string qualified_name)
	{
		auto parts = split(qualified_name, ".");
		Entity e = this;
		foreach( p; parts ){
			e = e.findChild(p);
			if( !e ){
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
}

final class DocGroup {
	Entity[] members;
	string text;

	this(Entity entity, string text)
	{
		this.members = [entity];
		this.text = text;
	}
}

final class Package : Entity {
	Package[] packages;
	Module[] modules;

	this(Entity parent, string name){ super(parent, name); }

	Module createModule(string name)
	{
		assert(findChild(name) is null, "Module already present");
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

	void iterateChildren(bool delegate(inout(Entity)) del)
	inout {
		foreach( p; packages ) if( !del(p) ) return;
		foreach( m; modules ) if( !del(m) ) return;
	}
}

final class Module : Entity{
	Declaration[] members;
	string file;

	this(Entity parent, string name){ super(parent, name); }

	void iterateChildren(bool delegate(inout(Entity)) del)
	inout{
		foreach( m; members ) if( !del(m) ) return;
	}
}

enum DeclarationKind {
	Variable,
	Function,
	Struct,
	Class,
	Interface,
	Enum,
	EnumMember,
	Alias,	
	Template,
}

enum Protection {
	Private,
	Package,
	Protected,
	Public
}

class Declaration : Entity {
	Protection protection = Protection.Public;
	int line;

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

	this(Entity parent, string name){ super(parent, name); }

	abstract void iterateChildren(bool delegate(inout(Entity)) del) inout;
}

class TypedDeclaration : Declaration {
	Type type;

	abstract @property DeclarationKind kind() const;

	this(Entity parent, string name){ super(parent, name); }

	abstract void iterateChildren(bool delegate(inout(Entity)) del) inout;
}

final class VariableDeclaration : TypedDeclaration {
	Value initializer;

	@property DeclarationKind kind() const { return DeclarationKind.Variable; }

	this(Entity parent, string name){ super(parent, name); }

	void iterateChildren(bool delegate(inout(Entity)) del) inout {}
}

final class FunctionDeclaration : TypedDeclaration {
	Type returnType;
	VariableDeclaration[] parameters;
	string[] attributes;

	@property DeclarationKind kind() const { return DeclarationKind.Function; }

	this(Entity parent, string name){ super(parent, name); }

	bool hasAttribute(string att) const { foreach( a; attributes ) if( a == att ) return true; return false; }

	void iterateChildren(bool delegate(inout(Entity)) del)
	inout {
		foreach( p; parameters ) del(p);
	}
}

class CompositeTypeDeclaration : TypedDeclaration {
	Declaration[] members;

	abstract @property DeclarationKind kind();
 
	this(Entity parent, string name){ super(parent, name); }

	void iterateChildren(bool delegate(inout(Entity)) del)
	inout {
		foreach( m; members ) if( !del(m) ) return;
	}
}

final class StructDeclaration : CompositeTypeDeclaration {
	@property DeclarationKind kind() const { return DeclarationKind.Struct; }

	this(Entity parent, string name){ super(parent, name); }
}

final class InterfaceDeclaration : CompositeTypeDeclaration {
	Type[] derivedInterfaces;

	@property DeclarationKind kind() const { return DeclarationKind.Interface; }

	this(Entity parent, string name){ super(parent, name); }
}

final class ClassDeclaration : CompositeTypeDeclaration {
	Type baseClass;
	Type[] derivedInterfaces;

	@property DeclarationKind kind() const { return DeclarationKind.Class; }

	this(Entity parent, string name){ super(parent, name); }
}

final class EnumDeclaration : CompositeTypeDeclaration {
	Type baseType;

	@property DeclarationKind kind() const { return DeclarationKind.Enum; }

	this(Entity parent, string name){ super(parent, name); }
}

final class EnumMemberDeclaration : Declaration {
	Value value;

	@property DeclarationKind kind() const { return DeclarationKind.EnumMember; }

	this(Entity parent, string name){ super(parent, name); }

	void iterateChildren(bool delegate(inout(Entity)) del) inout {}
}

final class AliasDeclaration : Declaration {
	Declaration targetDecl;
	Type targetType;

	@property DeclarationKind kind() const { return DeclarationKind.Alias; }

	this(Entity parent, string name){ super(parent, name); }

	void iterateChildren(bool delegate(inout(Entity)) del) inout {}
}

final class TemplateDeclaration : Declaration {
	string templateArgs;
	Declaration[] members;

	@property DeclarationKind kind() const { return DeclarationKind.Template; }

	this(Entity parent, string name){ super(parent, name); }

	void iterateChildren(bool delegate(inout(Entity)) del)
	inout {
		foreach( m; members ) del(m);
	}
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
	size_t arrayLength;
	// AA
	Type keyType;
	// Function/Delegate
	Type returnType;
	Type[] parameterTypes;
	string[] _parameterNames;
	Value[] _parameterDefaultValues;

	this() {}
	this(Declaration decl) { kind = TypeKind.Primitive; text = decl.nestedName; typeName = text; typeDecl = decl; }
}
