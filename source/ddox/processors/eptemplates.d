/**
	Merges eponymous templates to a single definition with template arguments.

	Copyright: © 2012-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.processors.eptemplates;

import ddox.api;
import ddox.entities;

import std.algorithm;


void mergeEponymousTemplates(Package root)
{
	import std.array : array;
	import std.string : strip;

	static bool canMerge(TemplateDeclaration templ, Declaration m)
	{
		// if we encounter any templated member, skip the
		// eponymous merge to avoid hiding the nested template
		// arguments/constraints
		if (cast(TemplateDeclaration)m || m.isTemplate) return false;

		// if both, the parent template and the member are documented,
		// abort the merge, so that the member documentation is shown
		// individually
		if (templ.docGroup.text.strip.length && m.docGroup.text.strip.length)
			return false;
		return true;
	}

	void processDecls(ref Declaration[] decls)
	{
		Declaration[] new_decls;
		foreach (d; decls) {
			if (auto templ = cast(TemplateDeclaration)d) {
				// process members recursively
				processDecls(templ.members);

				// search for eponymous template members
				Declaration[] epmembers = templ.members.filter!(m => m.name == templ.name).array;
				if (!epmembers.length || !epmembers.all!(m => canMerge(templ, m))) {
					// keep the template if there are no eponymous members or not all are mergeable
					new_decls ~= templ;
					continue;
				}

				foreach (m; epmembers) {
					m.templateArgs = templ.templateArgs;
					m.templateConstraint = templ.templateConstraint;
					m.isTemplate = true;
					m.protection = templ.protection;
					m.parent = templ.parent;
					if (templ.docGroup.text.strip.length) m.docGroup = templ.docGroup;
					m.inheritingDecl = templ.inheritingDecl;
				}

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
				if (auto comp = cast(CompositeTypeDeclaration)d)
					processDecls(comp.members);

				new_decls ~= d;
			}
		}
		decls = new_decls;
	}

	root.visit!Module((Module mod){
		processDecls(mod.members);
	});
}
