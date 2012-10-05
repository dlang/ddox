module ddox.htmlserver;

import ddox.api; // just so that rdmd picks it up
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

		res.renderCompat!("api.dt",
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

		res.renderCompat!("api-module.dt",
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
		}

		Info3 info;
		info.rootDir = req.rootDir;
		if( path_prefix.length ) info.rootDir ~= path_prefix[1 .. $];
		info.rootPackage = pack;
		info.mod = cast(Module)pack.lookup(req.params["modulename"]);
		if( !info.mod ) return;
		info.item = cast(Declaration)info.mod.lookup(req.params["itemname"]);
		if( !info.item ) return;
		info.docGroup = info.item.docGroup;

		switch( info.item.kind ){
			default: logWarn("Unknown API item kind: %s", info.item.kind); return;
			case DeclarationKind.Function:
				res.renderCompat!("api-function.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
				break;
			case DeclarationKind.Interface:
			case DeclarationKind.Class:
			case DeclarationKind.Struct:
			case DeclarationKind.Template:
				res.renderCompat!("api-composite.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
				break;
			case DeclarationKind.Enum:
				res.renderCompat!("api-enum.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
				break;
		}
	}

	if( path_prefix.length ) router.get(path_prefix, staticRedirect("path_prefix/"));
	router.get(path_prefix~"/", &showApi);
	router.get(path_prefix~"/:modulename", delegate(req, res){ res.redirect((path_prefix.length ? path_prefix ~ "/" : "/api/")~req.params["modulename"]~"/"); });
	router.get(path_prefix~"/:modulename/", &showApiModule);
	router.get(path_prefix~"/:modulename/:itemname", &showApiItem);
}