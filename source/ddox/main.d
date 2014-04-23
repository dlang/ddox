module ddox.main;

import ddox.ddoc;
import ddox.ddox;
import ddox.entities;
import ddox.htmlgenerator;
import ddox.htmlserver;
import ddox.jsonparser;
import ddox.jsonparser_old;

import vibe.core.core;
import vibe.core.file;
import vibe.data.json;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.operations;
import std.array;
import std.exception : enforce;
import std.file;
import std.getopt;
import std.stdio;
import std.string;


int ddoxMain(string[] args)
{
	if( args.length < 2 ){
		showUsage(args);
		return 1;
	}

	switch( args[1] ){
		default: showUsage(args); return 1;
		case "generate-html": return cmdGenerateHtml(args);
		case "serve-html": return cmdServeHtml(args);
		case "filter": return cmdFilterDocs(args);
	}
}

int cmdGenerateHtml(string[] args)
{
	GeneratorSettings gensettings;
	Package pack;
	if( auto ret = setupGeneratorInput(args, gensettings, pack) )
		return ret;

	generateHtmlDocs(Path(args[3]), pack, gensettings);
	return 0;
}

int cmdServeHtml(string[] args)
{
	string[] webfiledirs;
	getopt(args,
		config.passThrough,
		"web-file-dir", &webfiledirs);

	GeneratorSettings gensettings;
	Package pack;
	if( auto ret = setupGeneratorInput(args, gensettings, pack) )
		return ret;

	// register the api routes and start the server
	auto router = new URLRouter;
	registerApiDocs(router, pack, gensettings);

	foreach (dir; webfiledirs)
		router.get("*", serveStaticFiles(dir));

	writefln("Listening on port 8080...");
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	listenHTTP(settings, router);

	return runEventLoop();
}

int setupGeneratorInput(ref string[] args, out GeneratorSettings gensettings, out Package pack)
{
	string[] macrofiles;
	string[] overridemacrofiles;
	NavigationType navtype;
	string[] pack_order;
	string sitemapurl = "http://127.0.0.1/";
	bool lowercasenames = false;
	getopt(args,
		//config.passThrough,
		"std-macros", &macrofiles,
		"override-macros", &overridemacrofiles,
		"navigation-type", &navtype,
		"package-order", &pack_order,
		"sitemap-url", &sitemapurl,
		"lowercase-names", &lowercasenames);

	if( args.length < 3 ){
		showUsage(args);
		return 1;
	}

	setDefaultDdocMacroFiles(macrofiles);
	setOverrideDdocMacroFiles(overridemacrofiles);

	// parse the json output file
	auto docsettings = new DdoxSettings;
	docsettings.packageOrder = pack_order;
	pack = parseDocFile(args[2], docsettings);

	gensettings = new GeneratorSettings;
	gensettings.siteUrl = URL(sitemapurl);
	gensettings.navigationType = navtype;
	gensettings.lowerCaseNames = lowercasenames;
	return 0;
}

int cmdFilterDocs(string[] args)
{
	string[] excluded, included;
	Protection minprot = Protection.Private;
	bool keeputests = false;
	bool keepinternals = false;
	bool unittestexamples = true;
	bool nounittestexamples = false;
	bool justdoc = false;
	getopt(args,
		//config.passThrough,
		"ex", &excluded,
		"in", &included,
		"min-protection", &minprot,
		"only-documented", &justdoc,
		"keep-unittests", &keeputests,
		"keep-internals", &keepinternals,
		"unittest-examples", &unittestexamples, // deprecated, kept to not break existing scripts
		"no-unittest-examples", &nounittestexamples);

	if (keeputests) keepinternals = true;
	if (nounittestexamples) unittestexamples = false;

	string jsonfile;
	if( args.length < 3 ){
		showUsage(args);
		return 1;
	}

	Json filterProt(Json json, Json parent, Json last_decl, Json mod)
	{
		if (last_decl.type == Json.Type.undefined) last_decl = parent;

		string templateName(Json j){
			auto n = j.name.opt!string();
			auto idx = n.indexOf('(');
			if( idx >= 0 ) return n[0 .. idx];
			return n;
		}
	
		if( json.type == Json.Type.Object ){
			auto comment = json.comment.opt!string().strip();
			if( justdoc && comment.empty ){
				if( parent.type != Json.Type.Object || parent.kind.opt!string() != "template" || templateName(parent) != json.name.opt!string() )
					return Json.undefined;
			}
			
			Protection prot = Protection.Public;
			if( auto p = "protection" in json ){
				switch(p.get!string){
					default: break;
					case "private": prot = Protection.Private; break;
					case "package": prot = Protection.Package; break;
					case "protected": prot = Protection.Protected; break;
				}
			}
			if( comment == "private" ) prot = Protection.Private;
			if( prot < minprot ) return Json.undefined;

			auto name = json.name.opt!string();
			bool is_internal = name.startsWith("__");
			bool is_unittest = name.startsWith("__unittest");
			if (name.startsWith("_staticCtor") || name.startsWith("_staticDtor")) is_internal = true;
			else if (name.startsWith("_sharedStaticCtor") || name.startsWith("_sharedStaticDtor")) is_internal = true;

			if (unittestexamples && is_unittest && "comment" in json) {
				assert(last_decl.type == Json.Type.object, "Don't have a last_decl context.");
				try {
					string source = extractUnittestSourceCode(json, mod);
					if (last_decl.comment.opt!string.empty) {
						writefln("Warning: Cannot add documented unit test %s to %s, which is not documented.", name, last_decl.name.opt!string);
					} else {
						last_decl.comment ~= format("Example:\n%s\n---\n%s\n---\n", comment, source);
					}
				} catch (Exception e) {
					writefln("Failed to add documented unit test %s:%s as example: %s",
						mod.file.get!string(), json["line"].get!long, e.msg);
					return Json.undefined;
				}
			}
			
			if (!keepinternals && is_internal) return Json.undefined;

			if (!keeputests && is_unittest) return Json.undefined;

			if (auto mem = "members" in json)
				json.members = filterProt(*mem, json, Json.undefined, mod);
		} else if( json.type == Json.Type.Array ){
			auto last_child_decl = Json.undefined;
			Json[] newmem;
			foreach (m; json) {
				auto mf = filterProt(m, parent, last_child_decl, mod);
				if (mf.type == Json.Type.undefined) continue;
				if (mf.type == Json.Type.object && !mf.name.opt!string.startsWith("__unittest") && mf.comment.opt!string.strip != "ditto")
					last_child_decl = mf;
				newmem ~= mf;
			}
			return Json(newmem);
		}
		return json;
	}

	writefln("Reading doc file...");
	auto text = readText(args[2]);
	int line = 1;
	writefln("Parsing JSON...");
	auto json = parseJson(text, &line);

	writefln("Filtering modules...");
	Json[] dst;
	foreach (m; json) {
		if ("name" !in m) {
			writefln("No name for module %s - ignoring", m.file.opt!string);
			continue;
		}
		auto n = m.name.get!string;
		bool include = true;
		foreach (ex; excluded)
			if (n.startsWith(ex)) {
				include = false;
				break;
			}
		foreach (inc; included)
			if (n.startsWith(inc)) {
				include = true;
				break;
			}
		if (include) dst ~= filterProt(m, Json.undefined, Json.undefined, m);
	}

	writefln("Writing filtered docs...");
	auto buf = appender!string();
	writePrettyJsonString(buf, Json(dst));
	std.file.write(args[2], buf.data());

	return 0;
}

Package parseDocFile(string filename, DdoxSettings settings)
{
	writefln("Reading doc file...");
	auto text = readText(filename);
	int line = 1;
	writefln("Parsing JSON...");
	auto json = parseJson(text, &line);
	writefln("Parsing docs...");
	Package root;
	if( settings.oldJsonFormat ) root = parseJsonDocsOld(json);
	else root = parseJsonDocs(json);
	writefln("Finished parsing docs.");

	processDocs(root, settings);
	return root;
}

void showUsage(string[] args)
{
	string cmd;
	if( args.length >= 2 ) cmd = args[1];

	switch(cmd){
		default:
			writefln(
`Usage: %s <COMMAND> [args...]

    <COMMAND> can be one of:
        generate-html
        serve-html
        filter

Specifying only the command with no further arguments will print detailed usage
information.
`, args[0]);
			break;
		case "serve-html":
			writefln(
`Usage: %s serve-html <ddocx-input-file>
    --std-macros=FILE      File containing DDOC macros that will be available
    --override-macros=FILE File containing DDOC macros that will override local
                           definitions (Macros: section)
    --navigation-type=TYPE Change the type of navigation (ModuleList,
                           ModuleTree, DeclarationTree)
    --package-order=NAME   Causes the specified module to be ordered first. Can
                           be specified multiple times.
    --sitemap-url          Specifies the base URL used for sitemap generation
    --web-file-dir=DIR     Make files from dir available on the served site
`, args[0]);
			break;
		case "generate-html":
			writefln(
`Usage: %s generate-html <ddocx-input-file> <output-dir>
    --std-macros=FILE      File containing DDOC macros that will be available
    --override-macros=FILE File containing DDOC macros that will override local
                           definitions (Macros: section)
    --navigation-type=TYPE Change the type of navigation (ModuleList,
                           ModuleTree, DeclarationTree)
    --package-order=NAME   Causes the specified module to be ordered first. Can
                           be specified multiple times.
    --sitemap-url          Specifies the base URL used for sitemap generation
    --lowercase-names      Outputs all file names in lower case. This option is
                           useful on case insensitive file systems.
`, args[0]);
			break;
		case "filter":
			writefln(
`Usage: %s filter <ddocx-input-file> [options]
    --ex=PREFIX            Exclude modules with prefix
    --in=PREFIX            Force include of modules with prefix
    --min-protection=PROT  Remove items with lower protection level than
                           specified.
                           PROT can be: Public, Protected, Package, Private
    --only-documented      Remove undocumented entities.
    --keep-unittests       Do not remove unit tests from documentation.
                           Implies --keep-internals.
    --keep-internals       Do not remove symbols starting with two unterscores.
    --unittest-examples    Add documented unit tests as examples to the
                           preceeding declaration (deprecated, enabled by
                           default)
    --no-unittest-examples Don't convert documented unit tests to examples
`, args[0]);
	}
	if( args.length < 2 ){
	} else {

	}
}

private string extractUnittestSourceCode(Json decl, Json mod)
{
	auto filename = mod.file.get!string();
	enforce("line" in decl && "endline" in decl, "Missing line/endline fields.");
	auto from = decl["line"].get!long;
	auto to = decl.endline.get!long;

	// read the matching lines out of the file
	auto app = appender!string();
	long lc = 1;
	foreach (str; File(filename).byLine) {
		if (lc >= from) {
			app.put(str);
			app.put('\n');
		}
		if (++lc > to) break;
	}
	auto ret = app.data;

	// strip the "unittest { .. }" surroundings
	auto idx = ret.indexOf("unittest");
	enforce(idx >= 0, format("Missing 'unittest' for unit test at %s:%s.", filename, from));
	ret = ret[idx .. $];

	idx = ret.indexOf("{");
	enforce(idx >= 0, format("Missing opening '{' for unit test at %s:%s.", filename, from));
	ret = ret[idx+1 .. $];

	idx = ret.lastIndexOf("}");
	enforce(idx >= 0, format("Missing closing '}' for unit test at %s:%s.", filename, from));
	ret = ret[0 .. idx];

	// unindent lines according to the indentation of the first line
	app = appender!string();
	string indent;
	foreach (i, ln; ret.splitLines) {
		if (i == 1) {
			foreach (j; 0 .. ln.length)
				if (ln[j] != ' ' && ln[j] != '\t') {
					indent = ln[0 .. j];
					break;
				}
		}
		if (i > 0 || ln.strip.length > 0) {
			size_t j = 0;
			while (j < indent.length && !ln.empty) {
				if (ln.front != indent[j]) break;
				ln.popFront();
				j++;
			}
			app.put(ln);
			app.put('\n');
		}
	}
	return app.data;
}