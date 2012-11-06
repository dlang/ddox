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
import vibe.templ.diet; // just so that rdmd picks it up


void registerApiDocs(UrlRouter router, Package pack, string path_prefix = "/api", GeneratorSettings settings = null)
in {
	assert(path_prefix.length == 0 || path_prefix[0] == '/');
	assert(!path_prefix.endsWith('/'));
}
body {
	if( !settings ) settings = new GeneratorSettings;

	string linkTo(Entity ent, size_t level)
	{
		auto dst = appender!string();
		if( level ) foreach( i; 0 .. level ) dst.put("../");
		else dst.put("./");

		if( ent !is null && ent.parent !is null ){
			Entity[] nodes;
			size_t mod_idx = 0;
			while( ent ){
				if( cast(Module)ent ) mod_idx = nodes.length;
				nodes ~= ent;
				ent = ent.parent;
			}
			foreach_reverse(i, n; nodes[mod_idx .. $-1]){
				dst.put(n.name);
				if( i > 0 ) dst.put('.');
			}
			dst.put("/");
			foreach_reverse(i, n; nodes[0 .. mod_idx]){
				dst.put(n.name);
				if( i > 0 ) dst.put('.');
			}
		}
		return dst.data();
	}

	void showApi(HttpServerRequest req, HttpServerResponse res)
	{
		res.contentType = "text/html; charset=UTF-8";
		generateApiIndex(res.bodyWriter, pack, settings, ent => linkTo(ent, 0), req);
	}

	void showApiModule(HttpServerRequest req, HttpServerResponse res)
	{
		auto mod = cast(Module)pack.lookup(req.params["modulename"]);
		if( !mod ) return;

		res.contentType = "text/html; charset=UTF-8";
		generateModulePage(res.bodyWriter, pack, mod, settings, ent => linkTo(ent, 1), req);
	}

	void showApiItem(HttpServerRequest req, HttpServerResponse res)
	{
		auto mod = pack.lookup!Module(req.params["modulename"]);
		logDebug("mod: %s", mod !is null);
		if( !mod ) return;
		auto item = mod.lookup!Declaration(req.params["itemname"], false);
		logDebug("item: %s", item !is null);
		if( !item ) return;

		res.contentType = "text/html; charset=UTF-8";
		generateDeclPage(res.bodyWriter, pack, mod, item, settings, ent => linkTo(ent, 1), req);
	}

	if( path_prefix.length ) router.get(path_prefix, staticRedirect(path_prefix~"/"));
	router.get(path_prefix~"/", &showApi);
	router.get(path_prefix~"/:modulename", delegate(req, res){ res.redirect((path_prefix.length ? path_prefix ~ "/" : "/api/")~req.params["modulename"]~"/"); });
	router.get(path_prefix~"/:modulename/", &showApiModule);
	router.get(path_prefix~"/:modulename/:itemname", &showApiItem);
	router.get("*", serveStaticFiles("public"));
}