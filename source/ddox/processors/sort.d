module ddox.processors.sort;

import ddox.entities;

import std.algorithm;


void sortDocs(alias pred)(Package root)
{
	void sortDecl(Declaration decl)
	{
		
	}

	void sortModule(Module mod)
	{
		foreach( d; mod.members ) sortDecl(d);
		sort!pred(mod.members);
	}

	foreach( p; root.packages ) sortDocs!pred(p);
	foreach( m; root.modules ) sortModule(m);
	sort!pred(root.packages);
	sort!pred(root.modules);
}

