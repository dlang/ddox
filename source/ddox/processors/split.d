/**
	Splits documentation groups that contain different kinds of members.

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.processors.split;

import ddox.api;
import ddox.entities;

import std.algorithm;
import std.string;


void splitDocGroups(Package root, bool by_name, bool by_type, bool case_insensitive)
{
	bool match(Entity a, Entity b)
	{
		if (by_name && !case_insensitive && a.name != b.name) return false;
		if (by_name && case_insensitive && icmp(a.name, b.name) != 0) return false;
		if (by_type && a.kindCaption != b.kindCaption) return false;
		return true;
	}

	bool split_rec(Entity ent)
	{
		auto dg = ent.docGroup;
		if (dg) {
			DocGroup[] new_groups;
			next_child:
			foreach (child; dg.members) {
				foreach (g; new_groups)
					if (match(g.members[0], child)) {
						g.members ~= child;
						continue next_child;	
					}
				new_groups ~= new DocGroup(child, dg.text, dg.comment);
			}
			
			foreach (g; new_groups)
				foreach (m; g.members)
					m.docGroup = g;
		}

		ent.iterateChildren(&split_rec);

		return true;
	}

	split_rec(root);
}
