module ddox.htmlserver;

import ddox.api;
import ddox.ddoc; // just so that rdmd picks it up
import ddox.entities;

import std.string;
import vibe.core.log;
import vibe.http.router;
import vibe.templ.diet; // just so that rdmd picks it up


void registerApiDocs(UrlRouter router, Package pack, string path_prefix = "/api")
in {
	assert(path_prefix.length == 0 || path_prefix[0] == '/');
	assert(!path_prefix.endsWith('/'));
}
body {
	void showApi(HttpServerRequest req, HttpServerResponse res)
	{
		struct Info2 {
			string rootDir;
			Package rootPackage;
		}

		Info2 info;
		info.rootDir = req.rootDir;
		if( path_prefix.length ) info.rootDir ~= path_prefix[1 .. $];
		info.rootPackage = pack;

		res.renderCompat!("ddox.overview.dt",
			HttpServerRequest, "req",
			Info2*, "info")
			(Variant(req), Variant(&info));
	}

	void showApiModule(HttpServerRequest req, HttpServerResponse res)
	{
		struct Info2 {
			string rootDir;
			Package rootPackage;
			Module mod;
		}

		Info2 info;
		info.rootDir = req.rootDir;
		if( path_prefix.length ) info.rootDir ~= path_prefix[1 .. $];
		info.rootPackage = pack;
		info.mod = cast(Module)pack.lookup(req.params["modulename"]);
		if( !info.mod ) return;

		res.renderCompat!("ddox.module.dt",
			HttpServerRequest, "req",
			Info2*, "info")
			(Variant(req), Variant(&info));
	}

	void showApiItem(HttpServerRequest req, HttpServerResponse res)
	{
		struct Info3 {
			string rootDir;
			Package rootPackage;
			Module mod;
			Declaration item;
			DocGroup docGroup;
			DocGroup[] docGroups; // for multiple doc groups with the same name
		}

		Info3 info;
		info.rootDir = req.rootDir;
		if( path_prefix.length ) info.rootDir ~= path_prefix[1 .. $];
		info.rootPackage = pack;
		info.mod = pack.lookup!Module(req.params["modulename"]);
		logInfo("mod: %s", info.mod !is null);
		if( !info.mod ) return;
		info.item = info.mod.lookup!Declaration(req.params["itemname"], false);
		logInfo("item: %s", info.item !is null);
		if( !info.item ) return;
		info.docGroup = info.item.docGroup;
		info.docGroups = docGroups(info.mod.lookupAll!Declaration(req.params["itemname"]));

		switch( info.item.kind ){
			default: logWarn("Unknown API item kind: %s", info.item.kind); return;
			case DeclarationKind.Function:
				res.renderCompat!("ddox.function.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
				break;
			case DeclarationKind.Interface:
			case DeclarationKind.Class:
			case DeclarationKind.Struct:
			case DeclarationKind.Template:
				res.renderCompat!("ddox.composite.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
				break;
			case DeclarationKind.Enum:
				res.renderCompat!("ddox.enum.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
				break;
		}
	}

	if( path_prefix.length ) router.get(path_prefix, staticRedirect("path_prefix/"));
	router.get(path_prefix~"/", &showApi);
	router.get(path_prefix~"/:modulename", delegate(req, res){ res.redirect((path_prefix.length ? path_prefix ~ "/" : "/api/")~req.params["modulename"]~"/"); });
	router.get(path_prefix~"/:modulename/", &showApiModule);
	router.get(path_prefix~"/:modulename/:itemname", &showApiItem);
}