/**
	Contains definitions of the syntax tree elements.

	Copyright: © 2012-2015 RejectedSoftware e.K.
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
	CachedString name;
	DocGroup docGroup;

	this(Entity parent, string name)
	{
		this.parent = parent;
		this.name = name;
	}

	@property auto qualifiedName() const { return qualifiedPath().map!(e => e.name[]).joiner("."); }

	auto qualifiedPath()
	const {
		static struct R {
			private {
				Rebindable!(const(Entity)) m_current;
				Rebindable!(const(Entity)) m_back;
				size_t m_length;
			}

			@property const(Entity) front() { return m_current; }
			@property bool empty() const { return m_current is null; }
			@property size_t length() const { return m_length; }
			void popFront()
			{
				if (m_back is m_current) {
					m_current = null;
				} else {
					Rebindable!(const(Entity)) e = m_back;
					while (e.parent !is m_current)
						e = e.parent;
					m_current = e;
					m_length--;
				}
			}
		}

		R ret;
		ret.m_current = this;
		ret.m_length = 1;
		while (ret.m_current.parent && ret.m_current.parent.parent) {
			ret.m_current = ret.m_current.parent;
			ret.m_length++;
		}
		ret.m_back = this;
		return ret;
	}

	@property string moduleName()
	const {
		import std.conv : text;
		auto m = this.module_();
		return m ? text(m.qualifiedName) : null;
	}

	@property const(Module) module_()
	const {
		Rebindable!(const(Entity)) e = this;
		while (e && !cast(const(Module))e) e = e.parent;
		return cast(const(Module))e;
	}
	@property Module module_()
	{
		Entity e = this;
		while (e && !cast(Module)e) e = e.parent;
		return cast(Module)e;
	}

	@property string nestedName()
	const {
		string s = name;
		Rebindable!(const(Entity)) e = parent;
		while( e && e.parent ){
			if (cast(const(Module))e) break;
			s = e.name ~ "." ~ s;
			e = e.parent;
		}
		return s;
	}

	@property string kindCaption() const { return "Entity"; }

	bool isAncestorOf(in Entity node)
	const {
		auto n = rebindable(node);
		while( n ){
			if( n.parent is this ) return true;
			n = n.parent;
		}
		return false;
	}

	abstract void iterateChildren(scope bool delegate(Entity) del);

	final inout(T) findChild(T = Entity)(string name)
	inout {
		T ret;
		(cast(Entity)this).iterateChildren((ch) {
			if (ch.name == name) {
				ret = cast(T)ch;
				return ret is null;
			}
			return true;
		});
		return cast(inout)ret;
	}

	final inout(T)[] findChildren(T = Entity)(string name)
	inout {
		inout(T)[] ret;
		(cast(Entity)this).iterateChildren((ch) {
			if (ch.name == name) {
				auto t = cast(T)ch;
				if (t) ret ~= cast(inout)t;
			}
			return true;
		});
		return ret;
	}

	final inout(T) lookup(T = Entity)(string qualified_name, bool recurse = true)
	inout {
		assert(qualified_name.length > 0, "Looking up empty name.");
		auto parts = split(qualified_name, ".");
		Entity e = cast(Entity)this;
		foreach (i, p; parts) {
			if (i+1 < parts.length) {
				e = e.findChild(p);
				if (!e) break;
			} else {
				auto r = e.findChild!T(p);
				if (r) return cast(inout)r;
			}
		}
		static if (is(T == Declaration)) {
			if (auto decl = cast(inout(Declaration))this) {
				auto idx = decl.templateArgs.countUntil!(p => p.name.stripEllipsis() == qualified_name);
				if (idx >= 0) return cast(inout)decl.templateArgs[idx];
			}
		}
		if (recurse && parent) return cast(inout)parent.lookup!T(qualified_name);
		return null;
	}

	final inout(T)[] lookupAll(T = Entity)(string qualified_name)
	inout {
		assert(qualified_name.length > 0, "Looking up empty name.");
		auto parts = split(qualified_name, ".");
		Entity e = cast(Entity)this;
		foreach (i, p; parts) {
			if( i+1 < parts.length ) e = e.findChild(p);
			else return cast(inout)e.findChildren!T(p);
			if( !e ) return null;
		}
		return null;
	}

	final inout(Entity) lookdown(string qualified_name, bool stop_at_module_level = false)
	inout {
		auto parts = split(qualified_name, ".");
		Entity e = cast(Entity)this;
		foreach (p; parts) {
			e = e.findChild(p);
			if (!e) {
				if( stop_at_module_level && cast(Module)this ) return null;
				Entity ret;
				(cast(Entity)this).iterateChildren((ch){
					if (auto res = (cast()ch).lookdown(qualified_name)) {
						ret = res;
						return false;
					}
					return true; 
				});
				return cast(inout)ret;
			}
		}
		return cast(inout)e;
	}

	void visit(T)(scope void delegate(T) del)
	{
		if (auto t = cast(T)this) del(t);
		iterateChildren((ch) {
			ch.visit!T(del);
			return true;
		});
	}

	void visit(T)(scope void delegate(T) del)
	const {
		Entity uthis = cast(Entity)this;
		if (auto t = cast(Unqual!T)uthis) del(t);
		uthis.iterateChildren((ch) {
			(cast(const)ch).visit!T(del);
			return true;
		});
	}
}

final class DocGroup {
	Entity[] members;
	CachedString text;
	DdocComment comment;

	this(Entity entity, string text)
	{
		this.members = [entity];
		this.text = text;
		this.comment = new DdocComment(text);
	}

	this(Entity entity, string text, DdocComment comment)
	{
		this.members = [entity];
		this.text = text;
		this.comment = comment;
	}
}

final class Package : Entity {
	Package[] packages;
	Module[] modules;

	this(Entity parent, string name){ super(parent, name); }

	override @property string kindCaption() const { return "Package"; }

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

	override void iterateChildren(scope bool delegate(Entity) del)
	{
		foreach( p; packages ) if( !del(p) ) return;
		foreach( m; modules ) if( !del(m) ) return;
	}
}

final class Module : Entity{
	Declaration[] members;
	CachedString file;

	this(Entity parent, string name){ super(parent, name); }

	override @property string kindCaption() const { return "Module"; }

	/// Determines if this module is a "package.d" module.
	@property bool isPackageModule() { return parent && parent.findChild!Package(this.name); }

	override void iterateChildren(scope bool delegate(Entity) del)
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
	immutable(CachedString)[] attributes;
	int line;
	bool isTemplate;
	TemplateParameterDeclaration[] templateArgs;
	CachedString templateConstraint;

	override @property string kindCaption() const { return "Declaration"; }
	abstract @property Declaration dup();
	abstract @property DeclarationKind kind() const;
	@property inout(Declaration) parentDeclaration() inout { return cast(inout(Declaration))parent; }
	override @property Module module_() {
		Entity e = parent;
		while(e){
			if( auto m = cast(Module)e ) return m;
			e = e.parent;
		}
		assert(false, "Declaration without module?");
	}
	override @property const(Module) module_() const {
		Rebindable!(const(Entity)) e = parent;
		while(e){
			if( auto m = cast(const(Module))e ) return m;
			e = e.parent;
		}
		assert(false, "Declaration without module?");
	}

	this(Entity parent, string name){ super(parent, name); }

	abstract override void iterateChildren(scope bool delegate(Entity) del);

	protected void copyFrom(Declaration src)
	{
		this.docGroup = src.docGroup;
		this.inheritingDecl = src.inheritingDecl;
		this.protection = src.protection;
		this.attributes = src.attributes;
		this.line = src.line;
		this.templateArgs = src.templateArgs;
		this.templateConstraint = src.templateConstraint;
	}
}

class TypedDeclaration : Declaration {
	CachedType type;

	this(Entity parent, string name){ super(parent, name); }

	override @property string kindCaption() const { return "Typed declaration"; }

	abstract override @property DeclarationKind kind() const;

	abstract override void iterateChildren(scope bool delegate(Entity) del);

	protected override void copyFrom(Declaration src)
	{
		super.copyFrom(src);
		if (auto tsrc = cast(TypedDeclaration)src)
			this.type = tsrc.type;
	}
}

final class VariableDeclaration : TypedDeclaration {
	Value initializer;

	override @property string kindCaption() const { return "Variable"; }
	override @property VariableDeclaration dup() { auto ret = new VariableDeclaration(parent, name); ret.copyFrom(this); ret.initializer = initializer; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Variable; }

	this(Entity parent, string name){ super(parent, name); }

	override void iterateChildren(scope bool delegate(Entity) del) {}
}

final class FunctionDeclaration : TypedDeclaration {
	CachedType returnType;
	VariableDeclaration[] parameters;

	override @property string kindCaption() const { return "Function"; }
	override @property FunctionDeclaration dup() { auto ret = new FunctionDeclaration(parent, name); ret.copyFrom(this); ret.returnType = returnType; ret.parameters = parameters.dup; ret.attributes = attributes; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Function; }

	this(Entity parent, string name){ super(parent, name); }

	bool hasAttribute(string att) const { foreach( a; attributes ) if( a == att ) return true; return false; }

	override void iterateChildren(scope bool delegate(Entity) del)
	{
		foreach( p; parameters ) del(p);
	}
}

class CompositeTypeDeclaration : Declaration {
	Declaration[] members;

	override @property string kindCaption() const { return "Composite type"; }
	override abstract @property DeclarationKind kind() const;
 
	this(Entity parent, string name){ super(parent, name); }

	override void iterateChildren(scope bool delegate(Entity) del)
	{
		foreach( m; members ) if( !del(m) ) return;
	}
}

final class StructDeclaration : CompositeTypeDeclaration {
	override @property string kindCaption() const { return "Struct"; }
	override @property StructDeclaration dup() { auto ret = new StructDeclaration(parent, name); ret.copyFrom(this); ret.members = members; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Struct; }

	this(Entity parent, string name){ super(parent, name); }
}

final class UnionDeclaration : CompositeTypeDeclaration {
	override @property string kindCaption() const { return "Union"; }
	override @property UnionDeclaration dup() { auto ret = new UnionDeclaration(parent, name); ret.copyFrom(this); ret.members = members; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Union; }

	this(Entity parent, string name){ super(parent, name); }
}

final class InterfaceDeclaration : CompositeTypeDeclaration {
	CachedType[] derivedInterfaces;

	override @property string kindCaption() const { return "Interface"; }
	override @property InterfaceDeclaration dup() { auto ret = new InterfaceDeclaration(parent, name); ret.copyFrom(this); ret.members = members; ret.derivedInterfaces = derivedInterfaces.dup; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Interface; }

	this(Entity parent, string name){ super(parent, name); }
}

final class ClassDeclaration : CompositeTypeDeclaration {
	CachedType baseClass;
	CachedType[] derivedInterfaces;

	override @property string kindCaption() const { return "Class"; }
	override @property ClassDeclaration dup() { auto ret = new ClassDeclaration(parent, name); ret.copyFrom(this); ret.members = members; ret.baseClass = baseClass; ret.derivedInterfaces = derivedInterfaces.dup; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Class; }

	this(Entity parent, string name){ super(parent, name); }
}

final class EnumDeclaration : CompositeTypeDeclaration {
	CachedType baseType;

	override @property string kindCaption() const { return "Enum"; }
	override @property EnumDeclaration dup() { auto ret = new EnumDeclaration(parent, name); ret.copyFrom(this); ret.members = members; ret.baseType = baseType; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Enum; }

	this(Entity parent, string name){ super(parent, name); }
}

final class EnumMemberDeclaration : Declaration {
	Value value;

	override @property string kindCaption() const { return "Enum member"; }
	override @property EnumMemberDeclaration dup() { auto ret = new EnumMemberDeclaration(parent, name); ret.copyFrom(this); ret.value = value; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.EnumMember; }
	@property CachedType type() { if (!value) return CachedType.init; return value.type; }

	this(Entity parent, string name){ super(parent, name); }

	override void iterateChildren(scope bool delegate(Entity) del) {}
}

final class AliasDeclaration : Declaration {
	Declaration targetDecl;
	CachedType targetType;
	CachedString targetString;

	override @property string kindCaption() const { return "Alias"; }
	override @property AliasDeclaration dup() { auto ret = new AliasDeclaration(parent, name); ret.copyFrom(this); ret.targetDecl = targetDecl; ret.targetType = targetType; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Alias; }
	@property CachedType type() { return targetType; }

	this(Entity parent, string name){ super(parent, name); }

	override void iterateChildren(scope bool delegate(Entity) del) {}
}

final class TemplateDeclaration : Declaration {
	Declaration[] members;

	override @property string kindCaption() const { return "Template"; }
	override @property TemplateDeclaration dup() { auto ret = new TemplateDeclaration(parent, name); ret.copyFrom(this); ret.members = members.dup; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.Template; }

	this(Entity parent, string name){ super(parent, name); isTemplate = true; }

	override void iterateChildren(scope bool delegate(Entity) del)
	{
		foreach( m; members ) del(m);
	}
}

final class TemplateParameterDeclaration : TypedDeclaration {
	string defaultValue, specValue;

	override @property string kindCaption() const { return "Template parameter"; }
	override @property TemplateParameterDeclaration dup() { auto ret = new TemplateParameterDeclaration(parent, name); ret.copyFrom(this); ret.type = type; return ret; }
	override @property DeclarationKind kind() const { return DeclarationKind.TemplateParameter; }

	this(Entity parent, string name){ super(parent, name); }

	override void iterateChildren(scope bool delegate(Entity) del) {}
}

final class Value {
	CachedType type;
	CachedString valueString;

	this() {}
	this(CachedType type, string value_string) { this.type = type; this.valueString = value_string; }
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

struct CachedType {
	private {
		uint m_id = uint.max;

		static uint[const(Type)] s_typeIDs;
		static const(Type)[] s_types;
		static const(Type) s_emptyType;
	}

	static CachedType fromTypeDecl(Declaration decl)
	{
		import std.conv : to;
		Type tp;
		tp.kind = TypeKind.Primitive;
		tp.typeName = decl.qualifiedName.to!string;
		tp.typeDecl = decl;
		tp.text = decl.name;
		auto ct = CachedType(tp);
		auto existing = ct.typeDecl;
		//assert(!existing || existing is decl, "Replacing type decl "~existing.qualifiedName.to!string~" with "~decl.qualifiedName.to!string);
		return ct;
	}

	this(in ref Type tp)
	{
		this.type = tp;
	}

	this(Type tp)
	{
		this.type = tp;
	}

	bool opCast() const { return m_id != uint.max; }

	@property ref const(Type) type() const { return m_id == uint.max ? s_emptyType : s_types[m_id]; }
	@property ref const(Type) type(const(Type) tp)
	{
		if (auto pi = tp in s_typeIDs) {
			m_id = *pi;
		} else {
			if (!s_types.length) s_types.reserve(16384);

			m_id = cast(uint)s_types.length;
			s_types ~= tp;
			s_typeIDs[tp] = m_id;
		}
		return this.type;
	}

	alias type this;
}

struct Type {
	import std.typecons : Rebindable;

	TypeKind kind;

	immutable(CachedString)[] attributes;
	immutable(CachedString)[] modifiers;
	CachedString templateArgs;
	CachedString text; // original text as in DMDs JSON output
	// Primitive
	CachedString typeName;
	Rebindable!(const(Declaration)) typeDecl;
	// P, A, SA, AA
	CachedType elementType;
	// SA
	CachedString arrayLength;
	// AA
	CachedType keyType;
	// Function/Delegate
	CachedType returnType;
	immutable(CachedType)[] parameterTypes;
	immutable(CachedString)[] _parameterNames;
	immutable(Value)[] _parameterDefaultValues;
	public import std.traits : Variadic;
	Variadic variadic;

	static Type makePointer(CachedType base_type) { Type ret; ret.kind = TypeKind.Pointer; ret.elementType = base_type; return ret; }
	static Type makeArray(CachedType base_type) { Type ret; ret.kind = TypeKind.Array; ret.elementType = base_type; return ret; }
	static Type makeStaticArray(CachedType base_type, string length) { Type ret; ret.kind = TypeKind.StaticArray; ret.elementType = base_type; ret.arrayLength = length; return ret; }
	static Type makeAssociativeArray(CachedType value_type, CachedType key_type) { Type ret; ret.kind = TypeKind.AssociativeArray; ret.keyType = key_type; ret.elementType = value_type; return ret; }
	static Type makeFunction(CachedType return_type, immutable(CachedType)[] parameter_types) { Type ret; ret.kind = TypeKind.Function; ret.returnType = return_type; ret.parameterTypes = parameter_types; return ret; }
	static Type makeDelegate(CachedType return_type, immutable(CachedType)[] parameter_types) { Type ret; ret.kind = TypeKind.Delegate; ret.returnType = return_type; ret.parameterTypes = parameter_types; return ret; }

	equals_t opEquals(in Type other)
	const {
		if( kind != other.kind ) return false;
		if( attributes != other.attributes ) return false; // TODO use set comparison instead
		if( modifiers != other.modifiers ) return false; // TODO: use set comparison instead

		final switch( kind ){
			case TypeKind.Primitive: return typeName == other.typeName;
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

struct CachedString {
	private {
		uint m_id = uint.max;
		static uint[string] s_stringIDs;
		static string[] s_strings;
	}

	this(string str) { this.str = str; }

	string toString() const { return this.str; }

	@property size_t length() const { return this.str.length; }

	string opSlice(size_t lo, size_t hi) const { return this.str[lo .. hi]; }
	string opSlice() const { return this.str; }
	size_t opDollar() const { return this.length; }

	string opOpAssign(string op : "~")(string val) { return this.str = this.str ~ val; }

	@property string str() const { return m_id == uint.max ? "" : s_strings[m_id]; }
	@property string str(string value) {
		if (auto pi = value in s_stringIDs) {
			m_id = *pi;
		} else {
			if (!s_strings.length) {
				s_strings.length = 16384;
				s_strings.length = 0;
				s_strings.assumeSafeAppend();
			}

			// TODO: use a big pool of memory instead of individual allocations
			auto su = value.idup;
			auto id = cast(uint)s_strings.length;
			s_strings ~= su;
			s_stringIDs[su] = id;
			m_id = id;
		}
		return this.str;
	}

	alias str this;
}

private string stripEllipsis(string arg)
{
	return arg.endsWith("...") ? arg[0 .. $-3] : arg;
}
