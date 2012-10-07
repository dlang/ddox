module ddox.processors.sort;

import ddox.entities;

import std.algorithm;


void sortModules(alias pred)(Package root)
{
	void sortModule(Module mod)
	{
		sort!pred(mod.members);
	}

	foreach( p; root.packages ) sortModules!pred(p);
	foreach( m; root.modules ) sortModule(m);
	sort!pred(root.packages);
	sort!pred(root.modules);
}

void sortDecls(alias pred)(Package root)
{
	void sortDecl(Declaration decl)
	{
		if( auto td = cast(TemplateDeclaration)decl )
			sort!pred(td.members);
		else if( auto ctd = cast(CompositeTypeDeclaration)decl )
			sort!pred(ctd.members);
	}

	void sortModule(Module mod)
	{
		foreach( d; mod.members ) sortDecl(d);
	}

	foreach( p; root.packages ) sortDecls!pred(p);
	foreach( m; root.modules ) sortModule(m);
}
