/**
	Serves documentation on through HTTP server.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.htmlserver;

import ddox.api;
import ddox.ddoc; // just so that rdmd picks it up
import ddox.entities;
import ddox.htmlgenerator;
import ddox.settings;

import std.array;
import std.string;
import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;


void registerApiDocs(URLRouter router, Package pack, GeneratorSettings settings = null)
{
	if( !settings ) settings = new GeneratorSettings;

	string linkTo(in Entity ent_, size_t level)
	{
		import std.typecons : Rebindable;

		Rebindable!(const(Entity)) ent = ent_;
		auto dst = appender!string();

		if( level ) foreach( i; 0 .. level ) dst.put("../");
		else dst.put("./");

		if( ent !is null && ent.parent !is null ){
			Entity nested;
			if (
				// link parameters to their function
				(cast(FunctionDeclaration)ent.parent !is null &&
				 (nested = cast(VariableDeclaration)ent) !is null) ||
				// link enum members to their enum
				(!settings.enumMemberPages &&
				 cast(EnumDeclaration)ent.parent !is null &&
				 (nested = cast(EnumMemberDeclaration)ent) !is null))
				ent = ent.parent;

			const(Entity)[] nodes;
			size_t mod_idx = 0;
			while( ent ){
				if( cast(Module)ent ) mod_idx = nodes.length;
				nodes ~= ent;
				ent = ent.parent;
			}
			foreach_reverse(i, n; nodes[mod_idx .. $-1]){
				dst.put(n.name[]);
				if( i > 0 ) dst.put('.');
			}
			dst.put("/");
			foreach_reverse(i, n; nodes[0 .. mod_idx]){
				dst.put(n.name[]);
				if( i > 0 ) dst.put('.');
			}

			// link nested elements to anchor in parent, e.g. params, enum members
			if( nested ){
				dst.put('#');
				dst.put(nested.name[]);
			}
		}

		return dst.data();
	}

	void showApi(HTTPServerRequest req, HTTPServerResponse res)
	{
		res.contentType = "text/html; charset=UTF-8";
		generateApiIndex(res.bodyWriter, pack, settings, ent => linkTo(ent, 0), req);
	}

	void showApiModule(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto mod = pack.lookup!Module(req.params["modulename"]);
		if( !mod ) return;

		res.contentType = "text/html; charset=UTF-8";
		generateModulePage(res.bodyWriter, pack, mod, settings, ent => linkTo(ent, 1), req);
	}

	void showApiItem(HTTPServerRequest req, HTTPServerResponse res)
	{
		import std.algorithm;

		auto mod = pack.lookup!Module(req.params["modulename"]);
		logDebug("mod: %s", mod !is null);
		if( !mod ) return;
		auto items = mod.lookupAll!Declaration(req.params["itemname"]);
		logDebug("items: %s", items.length);
		if( !items.length ) return;

		auto docgroups = items.map!(i => i.docGroup).uniq.array;

		res.contentType = "text/html; charset=UTF-8";
		generateDeclPage(res.bodyWriter, pack, mod, items[0].nestedName, docgroups, settings, ent => linkTo(ent, 1), req);
	}

	void showSitemap(HTTPServerRequest req, HTTPServerResponse res)
	{
		res.contentType = "application/xml";
		generateSitemap(res.bodyWriter, pack, settings, ent => linkTo(ent, 0), req);
	}

	void showSearchResults(HTTPServerRequest req, HTTPServerResponse res)
	{
		import std.algorithm.iteration : map, splitter;
		import std.algorithm.sorting : sort;
		import std.algorithm.searching : canFind;
		import std.conv : to;

		auto terms = req.query.get("q", null).splitter(' ').map!(t => t.toLower()).array;

		size_t getPrefixIndex(string[] parts)
		{
			foreach_reverse (i, p; parts)
				foreach (t; terms)
					if (p.startsWith(t))
						return parts.length - 1 - i;
			return parts.length;
		}

		immutable(CachedString)[] getAttributes(Entity ent)
		{
			if (auto fdecl = cast(FunctionDeclaration)ent) return fdecl.attributes;
			else if (auto adecl = cast(AliasDeclaration)ent) return adecl.attributes;
			else if (auto tdecl = cast(TypedDeclaration)ent) return tdecl.type.attributes;
			else return null;
		}

		bool sort_pred(Entity a, Entity b)
		{
			// prefer non-deprecated matches
			auto adep = getAttributes(a).canFind("deprecated");
			auto bdep = getAttributes(b).canFind("deprecated");
			if (adep != bdep) return bdep;

			// normalize the names
			auto aname = a.qualifiedName.to!string.toLower(); // FIXME: avoid GC allocations
			auto bname = b.qualifiedName.to!string.toLower();

			auto anameparts = aname.split("."); // FIXME: avoid GC allocations
			auto bnameparts = bname.split(".");

			auto asname = anameparts[$-1];
			auto bsname = bnameparts[$-1];

			// prefer exact matches
			auto aexact = terms.canFind(asname);
			auto bexact = terms.canFind(bsname);
			if (aexact != bexact) return aexact;

			// prefer prefix matches
			auto apidx = getPrefixIndex(anameparts);
			auto bpidx = getPrefixIndex(bnameparts);
			if (apidx != bpidx) return apidx < bpidx;

			// prefer elements with less nesting
			if (anameparts.length != bnameparts.length)
				return anameparts.length < bnameparts.length;

			// prefer matches with a shorter name
			if (asname.length != bsname.length)
				return asname.length < bsname.length;

			// sort the rest alphabetically
			return aname < bname;
		}

		auto dst = appender!(Entity[]);
		if (terms.length)
			searchEntries(dst, pack, terms);
		dst.data.sort!sort_pred();

		static class Info : DocPageInfo {
			Entity[] results;
		}
		scope info = new Info;
		info.linkTo = (e) => linkTo(e, 0);
		info.settings = settings;
		info.rootPackage = pack;
		info.node = pack;
		info.results = dst.data;

		res.render!("ddox.search-results.dt", req, info);
	}

	string symbols_js;
	string symbols_js_md5;

	void showSymbolJS(HTTPServerRequest req, HTTPServerResponse res)
	{
		if (!symbols_js.length) {
			import std.digest.md;
			import vibe.stream.memory;
			auto os = createMemoryOutputStream;
			generateSymbolsJS(os, pack, settings, ent => linkTo(ent, 0));
			symbols_js = cast(string)os.data;
			symbols_js_md5 = '"' ~ md5Of(symbols_js).toHexString().idup ~ '"';
		}

		if (req.headers.get("If-None-Match", "") == symbols_js_md5) {
			res.statusCode = HTTPStatus.NotModified;
			res.writeVoidBody();
			return;
		}

		res.headers["ETag"] = symbols_js_md5;
		res.writeBody(symbols_js, "application/javascript");
	}

	auto path_prefix = settings.siteUrl.path.toString();
	if( path_prefix.endsWith("/") ) path_prefix = path_prefix[0 .. $-1];

	router.get(path_prefix~"/", &showApi);
	router.get(path_prefix~"/:modulename/", &showApiModule);
	router.get(path_prefix~"/:modulename/:itemname", &showApiItem);
	router.get(path_prefix~"/sitemap.xml", &showSitemap);
	router.get(path_prefix~"/symbols.js", &showSymbolJS);
	router.get(path_prefix~"/search", &showSearchResults);
	router.get("*", serveStaticFiles("public"));

	// convenience redirects (when leaving off the trailing slash)
	if( path_prefix.length ) router.get(path_prefix, staticRedirect(path_prefix~"/"));
	router.get(path_prefix~"/:modulename", (HTTPServerRequest req, HTTPServerResponse res){ res.redirect(path_prefix~"/"~req.params["modulename"]~"/"); });
}

private void searchEntries(R)(ref R dst, Entity root_ent, string[] search_terms) {
	bool[DocGroup] known_groups;
	void searchRec(Entity ent) {
		import std.conv : to;
		if ((!ent.docGroup || ent.docGroup !in known_groups) && matchesSearch(ent.qualifiedName.to!string, search_terms)) // FIXME: avoid GC allocations
			dst.put(ent);
		known_groups[ent.docGroup] = true;
		if (cast(FunctionDeclaration)ent) return;
		ent.iterateChildren((ch) { searchRec(ch); return true; });
	}
	searchRec(root_ent);
}

private bool matchesSearch(string name, in string[] terms)
{
	import std.algorithm.searching : canFind;

	foreach (t; terms)
		if (!name.toLower().canFind(t)) // FIXME: avoid GC allocations
			return false;
	return true;
}
