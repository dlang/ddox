module ddox.htmlgenerator;

import ddox.api;
import ddox.entities;

import std.array;
import std.variant;
import vibe.core.log;
import vibe.core.file;
import vibe.inet.path;
import vibe.http.server : HttpServerRequest;
import vibe.stream.stream;
import vibe.templ.diet;


class GeneratorSettings {
	bool navPackageTree = true;
}

/*
	structure:
	/index.html
	/pack1/pack2/module1.html
	/pack1/pack2/module1/member.html
	/pack1/pack2/module1/member.submember.html
*/

void generateHtmlDocs(Path dst_path, Package root)
{
	auto settings = new GeneratorSettings;

	string linkTo(Entity ent, size_t level)
	{
		auto dst = appender!string();
		if( level ) foreach( i; 0 .. level ) dst.put("../");
		else dst.put("./");

		if( ent !is null ){
			if( !ent.parent ){
				dst.put("index.html");
				return dst.data();
			}
			Entity[] nodes;
			int mod_idx = -1;
			while( ent ){
				if( cast(Module)ent ) mod_idx = nodes.length;
				nodes ~= ent;
				ent = ent.parent;
			}
			foreach_reverse(i, n; nodes[mod_idx .. $-1]){
				dst.put(n.name);
				if( i > 0 ) dst.put('/');
			}
			if( mod_idx == 0 ) dst.put(".html");
			else {
				dst.put('/');
				foreach_reverse(n; nodes[0 .. mod_idx]){
					dst.put(n.name);
					dst.put('.');
				}
				dst.put("html");
			}
		}
		return dst.data();
	}

	void visitDecl(Module mod, Declaration decl, Path path)
	{
		if( auto ctd = cast(CompositeTypeDeclaration)decl ){
			foreach( m; ctd.members )
				visitDecl(mod, m, path);
		} else if( auto td = cast(TemplateDeclaration)decl ){
			foreach( m; td.members )
				visitDecl(mod, m, path);
		}

		auto file = openFile(path ~ PathEntry(decl.nestedName~".html"), FileMode.CreateTrunc);
		scope(exit) file.close();
		generateDeclPage(file, root, mod, decl, settings, ent => linkTo(ent, path.length-dst_path.length));
	}

	void visitModule(Module mod, Path pack_path)
	{
		auto modpath = pack_path ~ PathEntry(mod.name);
		if( !existsFile(modpath) ) createDirectory(modpath);
		foreach( decl; mod.members ) visitDecl(mod, decl, modpath);
		logInfo("Generating module: %s", mod.qualifiedName);
		auto file = openFile(pack_path ~ PathEntry(mod.name~".html"), FileMode.CreateTrunc);
		scope(exit) file.close();
		generateModulePage(file, root, mod, settings, ent => linkTo(ent, pack_path.length-dst_path.length));
	}

	void visitPackage(Package p, Path path)
	{
		auto packpath = p.parent ? path ~ PathEntry(p.name) : path;
		if( !existsFile(packpath) ) createDirectory(packpath);
		foreach( sp; p.packages ) visitPackage(sp, packpath);
		foreach( m; p.modules ) visitModule(m, packpath);
	}

	if( !existsFile(dst_path) ) createDirectory(dst_path);
	auto idxfile = openFile(dst_path ~ PathEntry("index.html"), FileMode.CreateTrunc);
	scope(exit) idxfile.close();
	generateApiIndex(idxfile, root, settings, ent => linkTo(ent, 0));

	visitPackage(root, dst_path);
}

class DocPageInfo {
	string delegate(Entity ent) linkTo;
	GeneratorSettings settings;
	Package rootPackage;
	
	@property bool navPackageTree() const { return settings.navPackageTree; }
	string formatType(Type tp) { return .formatType(tp, linkTo); }
}

class DocModulePageInfo : DocPageInfo {
	Module mod;
}

class DocDeclPageInfo : DocModulePageInfo {
	Declaration item;
	DocGroup docGroup;
	DocGroup[] docGroups; // for multiple doc groups with the same name
}

void generateApiIndex(OutputStream dst, Package root_package, GeneratorSettings settings, string delegate(Entity) link_to, HttpServerRequest req = null)
{
	auto info = new DocPageInfo;
	info.linkTo = link_to;
	info.settings = settings;
	info.rootPackage = root_package;

	dst.parseDietFileCompat!("ddox.overview.dt",
		HttpServerRequest, "req",
		DocPageInfo, "info")
		(Variant(req), Variant(info));
}

void generateModulePage(OutputStream dst, Package root_package, Module mod, GeneratorSettings settings, string delegate(Entity) link_to, HttpServerRequest req = null)
{
	auto info = new DocModulePageInfo;
	info.linkTo = link_to;
	info.settings = settings;
	info.rootPackage = root_package;
	info.mod = mod;

	dst.parseDietFileCompat!("ddox.module.dt",
		HttpServerRequest, "req",
		DocModulePageInfo, "info")
		(Variant(req), Variant(info));
}

void generateDeclPage(OutputStream dst, Package root_package, Module mod, Declaration item, GeneratorSettings settings, string delegate(Entity) link_to, HttpServerRequest req = null)
{
	auto info = new DocDeclPageInfo;
	info.linkTo = link_to;
	info.settings = settings;
	info.rootPackage = root_package;
	info.mod = mod;
	info.item = item;
	info.docGroup = item.docGroup;
	info.docGroups = docGroups(mod.lookupAll!Declaration(item.nestedName));

	switch( info.item.kind ){
		default: logWarn("Unknown API item kind: %s", item.kind); return;
		case DeclarationKind.Function:
			dst.parseDietFileCompat!("ddox.function.dt", HttpServerRequest, "req", DocDeclPageInfo, "info")(Variant(req), Variant(info));
			break;
		case DeclarationKind.Interface:
		case DeclarationKind.Class:
		case DeclarationKind.Struct:
			dst.parseDietFileCompat!("ddox.composite.dt", HttpServerRequest, "req", DocDeclPageInfo, "info")(Variant(req), Variant(info));
			break;
		case DeclarationKind.Template:
			dst.parseDietFileCompat!("ddox.template.dt", HttpServerRequest, "req", DocDeclPageInfo, "info")(Variant(req), Variant(info));
			break;
		case DeclarationKind.Enum:
			dst.parseDietFileCompat!("ddox.enum.dt", HttpServerRequest, "req", DocDeclPageInfo, "info")(Variant(req), Variant(info));
			break;
	}
}
