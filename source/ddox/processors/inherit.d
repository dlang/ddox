/**
	Inherits non-existing members and documentation from anchestor classes/intefaces.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.processors.inherit;

import ddox.api;
import ddox.entities;

import std.algorithm : map;


void inheritDocs(Package root)
{
	bool[CompositeTypeDeclaration] visited;
	
	bool matches(Declaration a, Declaration b)
	{
		if (a.kind != b.kind) return false;
		if (a.name != b.name) return false;
		if (auto ctm = cast(TypedDeclaration)a)
			if (ctm.type != (cast(TypedDeclaration)b).type)
				return false;
		return true;
	}

	Declaration findMatching(Declaration[] pool, Declaration match)
	{
		foreach (m; pool) {
			if (matches(m, match))
				return m;
		}
		return null;
	}

	void inheritMembers(CompositeTypeDeclaration decl, Declaration[] parentmembers, const(Declaration) parent)
	{
		foreach (parentgrp; docGroups(parentmembers)) {
			DocGroup inhgrp;
			foreach (parentmem; parentgrp.members.map!(m => cast(Declaration)m)()) {
				if (parentmem.name == "this") continue;
				auto childmem = findMatching(decl.members, parentmem);
				if (!childmem || !childmem.docGroup.text.length) {
					Declaration newdecl;
					if (childmem) newdecl = childmem;
					else newdecl = parentmem.dup;
					if (!inhgrp) inhgrp = new DocGroup(newdecl, parentgrp.text);
					else inhgrp.members ~= newdecl;
					newdecl.docGroup = inhgrp;
					if (!childmem) {
						newdecl.inheritingDecl = parentmem;
						assert(newdecl.inheritingDecl && newdecl.inheritingDecl !is newdecl);
						decl.members ~= newdecl;
					}
				}
			}
		}
	}

	void scanInterface(InterfaceDeclaration decl)
	{
		if (decl in visited) return;
		foreach (i; decl.derivedInterfaces)
			if (i.typeDecl)
				scanInterface(cast(InterfaceDeclaration)i.typeDecl);
		visited[decl] = true;

		foreach (it; decl.derivedInterfaces)
			if (it.typeDecl)
				inheritMembers(decl, (cast(InterfaceDeclaration)it.typeDecl).members, it.typeDecl);
	}

	void scanClass(ClassDeclaration decl)
	{
		if (decl in visited) return;

		visited[decl] = true;

		if (decl.baseClass && decl.baseClass.typeDecl) scanClass(cast(ClassDeclaration)decl.baseClass.typeDecl);

		foreach (i; decl.derivedInterfaces)
			if (i.typeDecl)
				scanInterface(cast(InterfaceDeclaration)i.typeDecl);

		if (decl.baseClass && decl.baseClass.typeDecl)
			inheritMembers(decl, (cast(ClassDeclaration)decl.baseClass.typeDecl).members, decl.baseClass.typeDecl);
		foreach (i; decl.derivedInterfaces)
			if (i.typeDecl)
				inheritMembers(decl, (cast(InterfaceDeclaration)i.typeDecl).members, i.typeDecl);
	}

	void scanComposite(CompositeTypeDeclaration decl)
	{
		if (auto cd = cast(ClassDeclaration)decl) scanClass(cd);
		else if (auto cd = cast(InterfaceDeclaration)decl) scanInterface(cd);
		else {
			foreach (m; decl.members)
				if (auto dc = cast(CompositeTypeDeclaration)m)
					scanComposite(dc);
		}
	}

	void scanModule(Module mod)
	{
		foreach (d; mod.members)
			if (auto dc = cast(CompositeTypeDeclaration)d)
				scanComposite(dc);
	}

	void scanPackage(Package pack)
	{
		foreach (p; pack.packages)
			scanPackage(p);
		foreach (m; pack.modules)
			scanModule(m);
	}

	scanPackage(root);
}