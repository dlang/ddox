/**
	Central import for all DDOX functionality.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.ddox;

public import ddox.ddox;
public import ddox.entities;
public import ddox.htmlgenerator;
public import ddox.htmlserver;
public import ddox.settings;

import std.algorithm;
import std.string;

/**
	Applies settings such as sorting and documentation inheritance.
*/
void processDocs(Package root, DdoxSettings settings)
{
	import ddox.processors.eptemplates;
	import ddox.processors.inherit;
	import ddox.processors.sort;
	import ddox.processors.split;

	if (settings.mergeEponymousTemplates) {
		mergeEponymousTemplates(root);
	}
	if (settings.inheritDocumentation) {
		inheritDocs(root);
	}

	splitDocGroups(root, true, false, false);

	if (settings.moduleSort != SortMode.none) {
		auto mpred = sortPred(settings.moduleSort);
		sortModules!((a, b)  => mpred(a, b))(root);
		
		import std.algorithm;
		bool package_order(Package a, Package b){
			auto ia = settings.packageOrder.countUntil(a.name);
			auto ib = settings.packageOrder.countUntil(b.name);
			if( ia >= 0 && ib >= 0 ) return ia < ib;
			if( ia >= 0 ) return true;
			return false;
		}
		sort!(package_order, SwapStrategy.stable)(root.packages);
	}
	if( settings.declSort != SortMode.none ){
		auto dpred = sortPred(settings.declSort);
		sortDecls!((a, b)  => dpred(a, b))(root);
	}
}

/// private
private bool function(Entity, Entity) sortPred(SortMode mode)
{
	final switch (mode) {
		case SortMode.none:
			assert(false);
		case SortMode.name:
			return (a, b) {
				assert(a !is null && b !is null);
				return icmp(a.name, b.name) < 0;
			};
		case SortMode.protectionName:
			return (a, b) {
				assert(a !is null && b !is null);
				auto pa = Protection.Public;
				auto pb = Protection.Public;
				if (auto da = cast(Declaration)a) pa = da.protection;
				if (auto db = cast(Declaration)b) pb = db.protection;
				if (pa != pb) return pa > pb;
				return icmp(a.name, b.name) < 0;
			};
		case SortMode.protectionInheritanceName:
			return (a, b) {
				assert(a !is null && b !is null);
				auto pa = Protection.Public;
				auto pb = Protection.Public;
				bool ia, ib;
				if (auto da = cast(Declaration)a) pa = da.protection, ia = da.inheritingDecl !is null;
				if (auto db = cast(Declaration)b) pb = db.protection, ib = db.inheritingDecl !is null;
				if (pa != pb) return pa > pb;
				if (ia != ib) return ib;
				return icmp(a.name, b.name) < 0;
			};
	}
}

