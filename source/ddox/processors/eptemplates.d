/**
	Merges eponymous templates to a single definition with template arguments.

	Copyright: © 2012-2015 RejectedSoftware e.K.
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
				// process members recursively
				// FIXME: Drops template parameters of outer eponymous templates.
				//        However, this is the same behavior as that of Ddoc.
				processDecls(templ.members);

				// search for eponymous template members
				Declaration[] epmembers;
				foreach (m; templ.members)
					if (m.name == templ.name) {
						m.templateArgs = templ.templateArgs;
						m.templateConstraint = templ.templateConstraint;
						m.isTemplate = true;
						m.protection = templ.protection;
						m.parent = templ.parent;
						if (!m.docGroup.text.length)
							m.docGroup = templ.docGroup;
						else if (templ.docGroup.text.length)
							m.docGroup.text = templ.docGroup.text ~ "\n" ~ m.docGroup.text;
						m.inheritingDecl = templ.inheritingDecl;
						epmembers ~= m;
					}

				if (epmembers.length > 0) {
					// if we found some, replace all references of the original template with the new modified members
					foreach (i, m; templ.docGroup.members) {
						if (m !is templ) continue;
						auto newm = templ.docGroup.members[0 .. i];
						foreach (epm; epmembers)
							if (epm.docGroup is templ.docGroup)
								newm ~= epm;
						newm ~= templ.docGroup.members[i+1 .. $];
						templ.docGroup.members = newm;
						break;
					}
					new_decls ~= epmembers;
				} else {
					// keep the template if there are no eponymous members
					new_decls ~= templ;
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
