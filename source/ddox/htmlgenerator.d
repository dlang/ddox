/**
	Generates offline documentation in the form of HTML files.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.htmlgenerator;

import ddox.api;
import ddox.entities;
import ddox.settings;

import std.array;
import std.digest.md;
import std.format : formattedWrite;
import std.string : startsWith, toLower;
import std.variant;
import vibe.core.log;
import vibe.core.file;
import vibe.core.stream;
import vibe.data.json;
import vibe.inet.path;
import vibe.http.server;
import vibe.templ.diet;


/*
	structure:
	/index.html
	/pack1/pack2/module1.html
	/pack1/pack2/module1/member.html
	/pack1/pack2/module1/member.submember.html
*/

void generateHtmlDocs(Path dst_path, Package root, GeneratorSettings settings = null)
{
	import std.algorithm : splitter;
	import vibe.web.common : adjustMethodStyle;

	if( !settings ) settings = new GeneratorSettings;

	string[string] file_hashes;
	string[string] new_file_hashes;

	const hash_file_name = dst_path ~ "file_hashes.json";
	if (existsFile(hash_file_name)) {
		auto hfi = getFileInfo(hash_file_name);
		auto hf = readFileUTF8(hash_file_name);
		file_hashes = deserializeJson!(string[string])(hf);
	}

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

			auto dp = cast(VariableDeclaration)ent;
			auto dfn = ent.parent ? cast(FunctionDeclaration)ent.parent : null;
			if( dp && dfn ) ent = ent.parent;

			Entity[] nodes;
			size_t mod_idx = 0;
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
					dst.put(adjustMethodStyle(n.name, settings.fileNameStyle));
					dst.put('.');
				}
				dst.put("html");
			}

			// FIXME: must also work for multiple function overloads in separate doc groups!
			if( dp && dfn ){
				dst.put('#');
				dst.put(dp.name);
			}
		}

		return dst.data();
	}

	void collectChildren(Entity parent, ref DocGroup[][string] pages)
	{
		Declaration[] members;
		if (auto mod = cast(Module)parent) members = mod.members;
		else if (auto ctd = cast(CompositeTypeDeclaration)parent) members = ctd.members;
		else if (auto td = cast(TemplateDeclaration)parent) members = td.members;

		foreach (decl; members) {
			auto style = settings.fileNameStyle; // workaround for invalid value when directly used inside lamba
			auto name = decl.nestedName.splitter(".").map!(n => adjustMethodStyle(n, style)).join(".");
			auto pl = name in pages;
			if (pl && !canFind(*pl, decl.docGroup)) *pl ~= decl.docGroup;
			else if (!pl) pages[name] = [decl.docGroup];

			collectChildren(decl, pages);
		}
	}

	void writeHashedFile(Path filename, scope void delegate(OutputStream) del)
	{
		import vibe.stream.memory;
		assert(filename.startsWith(dst_path));

		auto str = new MemoryOutputStream;
		del(str);
		auto h = md5Of(str.data).toHexString.idup;
		auto relfilename = filename[dst_path.length .. $].toString();
		auto ph = relfilename in file_hashes;
		if (!ph || *ph != h) {
			//logInfo("do write %s", filename);
			writeFile(filename, str.data);
		}
		new_file_hashes[relfilename] = h;
	}

	void visitModule(Module mod, Path pack_path)
	{
		auto modpath = pack_path ~ PathEntry(mod.name);
		if (!existsFile(modpath)) createDirectory(modpath);
		logInfo("Generating module: %s", mod.qualifiedName);
		writeHashedFile(pack_path ~ PathEntry(mod.name~".html"), (stream) {
			generateModulePage(stream, root, mod, settings, ent => linkTo(ent, pack_path.length-dst_path.length));
		});

		DocGroup[][string] pages;
		collectChildren(mod, pages);
		foreach (name, decls; pages)
			writeHashedFile(modpath ~ PathEntry(name~".html"), (stream) {
				generateDeclPage(stream, root, mod, name, decls, settings, ent => linkTo(ent, modpath.length-dst_path.length));
			});
	}

	void visitPackage(Package p, Path path)
	{
		auto packpath = p.parent ? path ~ PathEntry(p.name) : path;
		if( !packpath.empty && !existsFile(packpath) ) createDirectory(packpath);
		foreach( sp; p.packages ) visitPackage(sp, packpath);
		foreach( m; p.modules ) visitModule(m, packpath);
	}

	dst_path.normalize();

	if( !dst_path.empty && !existsFile(dst_path) ) createDirectory(dst_path);

	writeHashedFile(dst_path ~ PathEntry("index.html"), (stream) {
		generateApiIndex(stream, root, settings, ent => linkTo(ent, 0));
	});

	writeHashedFile(dst_path ~ "symbols.js", (stream) {
		generateSymbolsJS(stream, root, settings, ent => linkTo(ent, 0));
	});

	writeHashedFile(dst_path ~ PathEntry("sitemap.xml"), (stream) {
		generateSitemap(stream, root, settings, ent => linkTo(ent, 0));
	});

	visitPackage(root, dst_path);

	// delete obsolete files
	foreach (f; file_hashes.byKey)
		if (f !in new_file_hashes) {
			try removeFile(dst_path ~ Path(f));
			catch (Exception e) logWarn("Failed to remove obsolete file '%s': %s", f, e.msg);
		}

	// write new file hash list
	writeFileUTF8(hash_file_name, new_file_hashes.serializeToJsonString());
}

class DocPageInfo {
	string delegate(Entity ent) linkTo;
	GeneratorSettings settings;
	Package rootPackage;
	Entity node;
	Module mod;
	DocGroup[] docGroups; // for multiple doc groups with the same name
	string nestedName;
	
	@property NavigationType navigationType() const { return settings.navigationType; }
	string formatType(Type tp, bool include_code_tags = true) { return .formatType(tp, linkTo, include_code_tags); }
	string formatDoc(DocGroup group, int hlevel, bool delegate(string) display_section)
	{
		return group.comment.renderSections(new DocGroupContext(group, linkTo), display_section, hlevel);
	}
}

void generateSitemap(OutputStream dst, Package root_package, GeneratorSettings settings, string delegate(Entity) link_to, HTTPServerRequest req = null)
{
	dst.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
	dst.write("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n");
	
	void writeEntry(string[] parts...){
		dst.write("<url><loc>");
		foreach( p; parts )
			dst.write(p);
		dst.write("</loc></url>\n");
	}

	void writeEntityRec(Entity ent){
		import std.string;
		if( !cast(Package)ent || ent is root_package ){
			auto link = link_to(ent);
			if( indexOf(link, '#') < 0 ) // ignore URLs with anchors
				writeEntry((settings.siteUrl ~ Path(link)).toString());
		}
		ent.iterateChildren((ch){ writeEntityRec(ch); return true; });
	}

	writeEntityRec(root_package);
	
	dst.write("</urlset>\n");
	dst.flush();
}

void generateSymbolsJS(OutputStream dst, Package root_package, GeneratorSettings settings, string delegate(Entity) link_to)
{
	import vibe.stream.wrapper;

	bool[string] visited;

	auto rng = StreamOutputRange(dst);

	void writeEntry(Entity ent) {
		if (cast(Package)ent || cast(TemplateParameterDeclaration)ent) return;
		if (ent.qualifiedName in visited) return;
		visited[ent.qualifiedName] = true;

		string kind = ent.classinfo.name.split(".")[$-1].toLower;
		string[] attributes;
		if (auto fdecl = cast(FunctionDeclaration)ent) attributes = fdecl.attributes;
		else if (auto adecl = cast(AliasDeclaration)ent) attributes = adecl.attributes;
		else if (auto tdecl = cast(TypedDeclaration)ent) attributes = tdecl.type.attributes;
		attributes = attributes.map!(a => a.startsWith("@") ? a[1 .. $] : a).array;
		(&rng).formattedWrite(`{name: '%s', kind: "%s", path: '%s', attributes: %s},`, ent.qualifiedName, kind, link_to(ent), attributes);
		rng.put('\n');
	}

	void writeEntryRec(Entity ent) {
		writeEntry(ent);
		if (cast(FunctionDeclaration)ent) return;
		ent.iterateChildren((ch) { writeEntryRec(ch); return true; });
	}

	rng.put("// symbol index generated by DDOX - do not edit\n");
	rng.put("var symbols = [\n");
	writeEntryRec(root_package);
	rng.put("];\n");
}

void generateApiIndex(OutputStream dst, Package root_package, GeneratorSettings settings, string delegate(Entity) link_to, HTTPServerRequest req = null)
{
	auto info = new DocPageInfo;
	info.linkTo = link_to;
	info.settings = settings;
	info.rootPackage = root_package;
	info.node = root_package;

	dst.parseDietFile!("ddox.overview.dt", req, info);
}

void generateModulePage(OutputStream dst, Package root_package, Module mod, GeneratorSettings settings, string delegate(Entity) link_to, HTTPServerRequest req = null)
{
	auto info = new DocPageInfo;
	info.linkTo = link_to;
	info.settings = settings;
	info.rootPackage = root_package;
	info.mod = mod;
	info.node = mod;
	info.docGroups = null;

	dst.parseDietFile!("ddox.module.dt", req, info);
}

void generateDeclPage(OutputStream dst, Package root_package, Module mod, string nested_name, DocGroup[] docgroups, GeneratorSettings settings, string delegate(Entity) link_to, HTTPServerRequest req = null)
{
	import std.algorithm : sort;

	auto info = new DocPageInfo;
	info.linkTo = link_to;
	info.settings = settings;
	info.rootPackage = root_package;
	info.mod = mod;
	info.node = mod;
	info.docGroups = docgroups;//docGroups(mod.lookupAll!Declaration(nested_name));
	sort!((a, b) => cmpKind(a.members[0], b.members[0]))(info.docGroups);
	info.nestedName = nested_name;

	dst.parseDietFile!("ddox.docpage.dt", req, info);
}

private bool cmpKind(Entity a, Entity b)
{
	static immutable kinds = [
		DeclarationKind.Variable,
		DeclarationKind.Function,
		DeclarationKind.Struct,
		DeclarationKind.Union,
		DeclarationKind.Class,
		DeclarationKind.Interface,
		DeclarationKind.Enum,
		DeclarationKind.EnumMember,
		DeclarationKind.Template,
		DeclarationKind.TemplateParameter,
		DeclarationKind.Alias
	];

	auto ad = cast(Declaration)a;
	auto bd = cast(Declaration)b;

	if (!ad && !bd) return false;
	if (!ad) return false;
	if (!bd) return true;

	auto ak = kinds.countUntil(ad.kind);
	auto bk = kinds.countUntil(bd.kind);

	if (ak < 0 && bk < 0) return false;
	if (ak < 0) return false;
	if (bk < 0) return true;

	return ak < bk;
}
