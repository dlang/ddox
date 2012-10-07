module ddox.htmlserver;

import ddox.api;
import ddox.ddoc; // just so that rdmd picks it up
import ddox.entities;
import ddox.htmlgenerator;

import std.string;
import vibe.core.log;
import vibe.http.router;
import vibe.templ.diet; // just so that rdmd picks it up


void registerApiDocs(UrlRouter router, Package pack, string path_prefix = "/api", bool nav_package_tree = true)
in {
	assert(path_prefix.length == 0 || path_prefix[0] == '/');
	assert(!path_prefix.endsWith('/'));
}
body {
	auto settings = new GeneratorSettings;
	settings.navPackageTree = nav_package_tree;

	void showApi(HttpServerRequest req, HttpServerResponse res)
	{
		res.contentType = "text/html; charset=UTF-8";
		generateApiIndex(res.bodyWriter, pack, settings, req);
	}

	void showApiModule(HttpServerRequest req, HttpServerResponse res)
	{
		auto mod = cast(Module)pack.lookup(req.params["modulename"]);
		if( !mod ) return;

		res.contentType = "text/html; charset=UTF-8";
		generateModulePage(res.bodyWriter, pack, mod, settings, req);
	}

	void showApiItem(HttpServerRequest req, HttpServerResponse res)
	{
		auto mod = pack.lookup!Module(req.params["modulename"]);
		logInfo("mod: %s", mod !is null);
		if( !mod ) return;
		auto item = mod.lookup!Declaration(req.params["itemname"], false);
		logInfo("item: %s", item !is null);
		if( !item ) return;

		res.contentType = "text/html; charset=UTF-8";
		generateDeclPage(res.bodyWriter, pack, mod, item, settings, req);
	}

	if( path_prefix.length ) router.get(path_prefix, staticRedirect("path_prefix/"));
	router.get(path_prefix~"/", &showApi);
	router.get(path_prefix~"/:modulename", delegate(req, res){ res.redirect((path_prefix.length ? path_prefix ~ "/" : "/api/")~req.params["modulename"]~"/"); });
	router.get(path_prefix~"/:modulename/", &showApiModule);
	router.get(path_prefix~"/:modulename/:itemname", &showApiItem);
}