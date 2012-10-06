module ddox.processors.inherit;

import ddox.api;
import ddox.entities;

void inheritDocs(Package root)
{
	bool[CompositeTypeDeclaration] visited;
	
	bool matches(Declaration a, Declaration b)
	{
		if( a.kind != b.kind ) return false;
		if( a.name != b.name ) return false;
		if( auto ctm = cast(TypedDeclaration)a )
			if( ctm.type != (cast(TypedDeclaration)b).type )
				return false;
		return true;
	}
	Declaration findMatching(Declaration[] pool, Declaration match)
	{
		foreach( m; pool ){
			if( matches(m, match) )
				return m;
		}
		return null;
	}

	void inheritMembers(CompositeTypeDeclaration decl, Declaration[] members, Declaration parent)
	{
		foreach( dg; docGroups(members) ){
			bool found = false;

			DocGroup idg;
			foreach( dgm_; dg.members ){
				auto dgm = cast(Declaration)dgm_;
				auto match = findMatching(decl.members, dgm);
				if( !match ){
					auto im = dgm.dup;
					im.inheritingDecl = dgm;
					if( !idg ) idg = new DocGroup(im, dg.text);
					else idg.members ~= im;
					decl.members ~= im;
				} else if( dg.text.length ){
					match.docGroup.text = dg.text;
				}
			}
		}
	}

	void scanInterface(InterfaceDeclaration decl)
	{
		if( decl in visited ) return;
		foreach( i; decl.derivedInterfaces )
			if( i.typeDecl )
				scanInterface(cast(InterfaceDeclaration)i.typeDecl);
		visited[decl] = true;

		foreach( it; decl.derivedInterfaces )
			if( it.typeDecl )
				inheritMembers(decl, (cast(InterfaceDeclaration)it.typeDecl).members, it.typeDecl);
	}

	void scanClass(ClassDeclaration decl)
	{
		if( decl in visited ) return;
		if( decl.baseClass && decl.baseClass.typeDecl ) scanClass(cast(ClassDeclaration)decl.baseClass.typeDecl);
		foreach( i; decl.derivedInterfaces )
			if( i.typeDecl )
				scanInterface(cast(InterfaceDeclaration)i.typeDecl);

		visited[decl] = true;
		if( decl.baseClass && decl.baseClass.typeDecl )
			inheritMembers(decl, (cast(ClassDeclaration)decl.baseClass.typeDecl).members, decl.baseClass.typeDecl);
		foreach( i; decl.derivedInterfaces )
			if( i.typeDecl )
				inheritMembers(decl, (cast(InterfaceDeclaration)i.typeDecl).members, i.typeDecl);
	}

	void scanComposite(CompositeTypeDeclaration decl)
	{
		if( auto cd = cast(ClassDeclaration)decl ) scanClass(cd);
		else if( auto cd = cast(InterfaceDeclaration)decl ) scanInterface(cd);
		else {
			foreach( m; decl.members )
				if( auto dc = cast(CompositeTypeDeclaration)m )
					scanComposite(dc);
		}
	}

	void scanModule(Module mod)
	{
		foreach( d; mod.members )
			if( auto dc = cast(CompositeTypeDeclaration)d )
				scanComposite(dc);
	}

	void scanPackage(Package pack)
	{
		foreach( p; pack.packages )
			scanPackage(p);
		foreach( m; pack.modules )
			scanModule(m);
	}

	scanPackage(root);
}