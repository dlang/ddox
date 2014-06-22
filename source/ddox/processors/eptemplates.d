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
	void processDecls(ref Declaration[] decls)
	{
		Declaration[] new_decls;
		foreach (d; decls) {
			if (auto templ = cast(TemplateDeclaration)d) {
				// search for eponymous template members
				Declaration[] epmembers;
				foreach (m; templ.members)
					if (m.name == templ.name) {
						m.templateArgs = templ.templateArgs;
						m.isTemplate = true;
						m.parent = templ.parent;
						if (templ.docGroup.text.length)
							m.docGroup = templ.docGroup;
						m.inheritingDecl = templ.inheritingDecl;
						epmembers ~= m;
					}

				if (epmembers.length > 0) {
					// if we found some, replace all references of the original template with the new modified members
					foreach (i, m; templ.docGroup.members) {
						auto newm = templ.docGroup.members[0 .. i];
						foreach (epm; epmembers) newm ~= epm;
						newm ~= templ.docGroup.members[i+1 .. $];
						templ.docGroup.members = newm;
						break;
					}
					new_decls ~= epmembers;
				} else {
					// else keep the template and continue with its children
					new_decls ~= templ;
					processDecls(templ.members);
				}
			} else new_decls ~= d;

			if (auto comp = cast(CompositeTypeDeclaration)d)
				processDecls(comp.members);
		}
		decls = new_decls;
	}

	root.visit!Module((mod){
		processDecls(mod.members);
	});
}
