module ddox.main;

import std.exception : enforce;
import std.getopt;
import std.stdio;


int ddoxMain(string[] args)
{
	import ddox.commands;
	bool help;
	getopt(args, config.passThrough, "h|help", &help);

	if( args.length < 2 || help ){
		showUsage(args);
		return help ? 0 : 1;
	}

	if( args[1] == "generate-html" && args.length >= 4 )
		return cmdGenerateHtml(args);
	if( args[1] == "serve-html" && args.length >= 3 )
		return cmdServeHtml(args);
	if( args[1] == "filter" && args.length >= 3 )
		return cmdFilterDocs(args);
	if( args[1] == "serve-test" && args.length >= 3 )
		return cmdServeTest(args);
	showUsage(args);
	return 1;
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

 -h --help                 Show this help

Use <COMMAND> -h|--help to get detailed usage information for a command.
`, args[0]);
			break;
		case "serve-html":
			writefln(
`Usage: %s serve-html <ddocx-input-file>
    --std-macros=FILE      File containing DDOC macros that will be available
    --override-macros=FILE File containing DDOC macros that will override local
                           definitions (Macros: section)
    --navigation-type=TYPE Change the type of navigation (ModuleList,
                           ModuleTree (default), DeclarationTree)
    --package-order=NAME   Causes the specified module to be ordered first. Can
                           be specified multiple times.
    --sitemap-url          Specifies the base URL used for sitemap generation
    --module-sort=MODE     The sort order used for lists of modules
    --decl-sort=MODE       The sort order used for declaration lists
    --web-file-dir=DIR     Make files from dir available on the served site
    --enum-member-pages    Generate a single page per enum member
    --html-style=STYLE     Sets the HTML output style, either pretty (default)
                           or compact.
    --hyphenate            hyphenate text
 -h --help                 Show this help

The following values can be used as sorting modes: none, name, protectionName,
protectionInheritanceName
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
    --module-sort=MODE     The sort order used for lists of modules
    --decl-sort=MODE       The sort order used for declaration lists
    --file-name-style=STY  Sets a translation style for symbol names to file
                           names. Use this instead of --lowercase-name.
                           Possible values for STY:
                             unaltered, camelCase, pascalCase, lowerCase,
                             upperCase, lowerUnderscored, upperUnderscored
    --lowercase-names      DEPRECATED: Outputs all file names in lower case.
                           This option is useful on case insensitive file
                           systems.
    --enum-member-pages    Generate a single page per enum member
    --html-style=STYLE     Sets the HTML output style, either pretty (default)
                           compact or .
    --hyphenate            hyphenate text
 -h --help                 Show this help

The following values can be used as sorting modes: none, name, protectionName,
protectionInheritanceName
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
    --keep-internals       Do not remove symbols starting with two underscores.
    --unittest-examples    Add documented unit tests as examples to the
                           preceding declaration (deprecated, enabled by
                           default)
    --no-unittest-examples Don't convert documented unit tests to examples
 -h --help                 Show this help
`, args[0]);
	}
	if( args.length < 2 ){
	} else {

	}
}
