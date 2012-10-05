module app;

import ddox.htmlserver;
import ddox.jsonparser;

import vibe.core.core;
import vibe.core.file;
import vibe.http.router;
import vibe.http.server;
import vibe.data.json;
import std.file;
import std.getopt;
import std.stdio;


int main(string[] args)
{
	if( args.length < 2 ){
		showUsage(args);
		return 1;
	}

	switch( args[1] ){
		default: showUsage(args); return 1; break;
		case "generate-html": return generateHtml(args);
		case "serve-html": return serveHtml(args);
	}
}

int processDocs(string[] args)
{
	/*if( args.length < 3 || args.length > 4 ){
		showUsage(args);
		return 1;
	}

	auto input = args[2];
	auto output = args.length > 3 ? args[3] : "ddox.json";

	auto srctext = readText(input);
	int line = 1;
	auto dmd_json = parseJson(srctext, &line);
	
	auto proc = new DocProcessor;
	auto dldoc_json = proc.processProject(dmd_json);
	
	auto dst = appender!string();
	toPrettyJson(dst, dldoc_json);
	std.file.write(args[2], dst.data());*/

	return 0;
}

int generateHtml(string[] args)
{
	return 0;
}

int serveHtml(string[] args)
{
	string jsonfile;
	if( args.length < 3 ){
		showUsage(args);
		return 1;
	}
	jsonfile = args[2];

	// parse the json output file
	auto text = readText(jsonfile);
	int line = 1;
	auto json = parseJson(text, &line);
	auto pack = parseJsonDocs(json);

	// register the api routes and start the server
	auto router = new UrlRouter;
	registerApiDocs(router, pack, "");

	writefln("Listening on port 8080...");
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	listenHttp(settings, router);

	startListening();
	return runEventLoop();
}

void showUsage(string[] args)
{
	string cmd;
	if( args.length >= 2 ) cmd = args[1];

	switch(cmd){
		default:
			writefln(
`Usage: %s <COMMAND> [--help] (args...)
	
	<COMMAND> can be one of:
		generate-html
		serve-html
`, args[0]);
			break;
		case "serve-html":
			writefln(
`Usage: %s generate-html <ddocx-input-file>
`, args[0]);
			break;
			break;
		case "generate-html":
			writefln(
`Usage: %s generate-html <ddocx-input-file> <output-dir>
`, args[0]);
			break;
	}
	if( args.length < 2 ){
	} else {

	}
}