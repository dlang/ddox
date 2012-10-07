module ddox.htmlgenerator;

import ddox.api;
import ddox.entities;

import std.variant;
import vibe.core.log;
import vibe.http.server : HttpServerRequest;
import vibe.stream.stream;
import vibe.templ.diet;


class GeneratorSettings {
	bool navPackageTree = true;
}

void generate(Package pack)
{

}

void generateApiIndex(OutputStream dst, Package root_package, GeneratorSettings settings, HttpServerRequest req)
{
	struct Info2 {
		string rootDir;
		bool navPackageTree;
		Package rootPackage;
	}

	Info2 info;
	info.rootDir = "";
	info.navPackageTree = settings.navPackageTree;
	info.rootPackage = root_package;

	dst.parseDietFileCompat!("ddox.overview.dt",
		HttpServerRequest, "req",
		Info2*, "info")
		(Variant(req), Variant(&info));
}

void generateModulePage(OutputStream dst, Package root_package, Module mod, GeneratorSettings settings, HttpServerRequest req)
{
	struct Info2 {
		string rootDir;
		bool navPackageTree;
		Package rootPackage;
		Module mod;
	}

	Info2 info;
	info.rootDir = "../";
	info.navPackageTree = settings.navPackageTree;
	info.rootPackage = root_package;
	info.mod = mod;

	dst.parseDietFileCompat!("ddox.module.dt",
		HttpServerRequest, "req",
		Info2*, "info")
		(Variant(req), Variant(&info));
}

void generateDeclPage(OutputStream dst, Package root_package, Module mod, Declaration item, GeneratorSettings settings, HttpServerRequest req)
{
	struct Info3 {
		string rootDir;
		bool navPackageTree;
		Package rootPackage;
		Module mod;
		Declaration item;
		DocGroup docGroup;
		DocGroup[] docGroups; // for multiple doc groups with the same name
	}

	Info3 info;
	info.rootDir = "../";
	info.navPackageTree = settings.navPackageTree;
	info.rootPackage = root_package;
	info.mod = mod;
	info.item = item;
	info.docGroup = item.docGroup;
	info.docGroups = docGroups(mod.lookupAll!Declaration(item.nestedName));

	switch( info.item.kind ){
		default: logWarn("Unknown API item kind: %s", item.kind); return;
		case DeclarationKind.Function:
			dst.parseDietFileCompat!("ddox.function.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
			break;
		case DeclarationKind.Interface:
		case DeclarationKind.Class:
		case DeclarationKind.Struct:
			dst.parseDietFileCompat!("ddox.composite.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
			break;
		case DeclarationKind.Template:
			dst.parseDietFileCompat!("ddox.template.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
			break;
		case DeclarationKind.Enum:
			dst.parseDietFileCompat!("ddox.enum.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
			break;
	}
}
