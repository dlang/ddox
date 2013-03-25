/**
	Sorts packages, modules and definitions in the syntax tree.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
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
		if( auto td = cast(TemplateDeclaration)decl ){
			foreach (sd; td.members) sortDecl(sd);
			sort!pred(td.members);
		}
		else if( auto ctd = cast(CompositeTypeDeclaration)decl ){
			foreach (sd; ctd.members) sortDecl(sd);
			sort!pred(ctd.members);
		}
	}

	void sortModule(Module mod)
	{
		foreach( d; mod.members ) sortDecl(d);
	}

	foreach( p; root.packages ) sortDecls!pred(p);
	foreach( m; root.modules ) sortModule(m);
}
