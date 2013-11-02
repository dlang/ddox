/**
	Merges eponymous templates to a single definition with template arguments.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.processors.eptemplates;

import ddox.api;
import ddox.entities;

import std.algorithm;


void mergeEponymousTemplates(Package root)
{
	void processDecls(Declaration[] decls)
	{
		foreach( ref d; decls ){
			if( auto templ = cast(TemplateDeclaration)d ){
				//if( templ.members.length == 1 && templ.members[0].name == templ.name ){
				auto idx = templ.members.countUntil!(m => m.name == templ.name)();
				if( idx >= 0 ){
					templ.members[idx].templateArgs = templ.templateArgs;
					templ.members[idx].isTemplate = true;
					templ.members[idx].parent = templ.parent;
					templ.members[idx].docGroup = templ.docGroup;
					templ.members[idx].inheritingDecl = templ.inheritingDecl;
					foreach( ref m; templ.docGroup.members )
						if( m is templ ) m = templ.members[idx];
					d = templ.members[idx];
				} else processDecls(templ.members);
			}

			if( auto comp = cast(CompositeTypeDeclaration)d ){
				processDecls(comp.members);
			}
		}
	}

	root.visit!Module((mod){
		processDecls(mod.members);
	});
}
