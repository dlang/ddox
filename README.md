DDOX documentation engine
==========================

This is an alternative documentation generator for programs written in the D programming language. It aims to be fully compatible with Ddoc (the documentation generator built into the D compiler). Additional features include:

 - Advanced page-per-symbol layout based on Diet templates
 - Full automatic cross-referencing
 - Automatically generated index, search database and site map
 - Filtering of symbols and modules based on their name and protection level
 - Integrated web server for fast local documentation serving
 - Directly embeddable into vibe.d applications

For real world examples see the [vibe.d API documentation](http://vibed.org/api/) and the [D standard library documentation](http://dlang.org/library/index.html).

[![Build Status](https://travis-ci.org/rejectedsoftware/ddox.svg)](https://travis-ci.org/rejectedsoftware/ddox)


First steps
-----------

1. Install [dub](https://github.com/dlang/dub/)
2. Generate JSON for your project by adding the command line switches `-D -X -Xfdocs.json` to your DMD command line (Note that you may need to clean up all the generated .html files afterwards)
3. Check out ddox and run `dub build` from its root folder

Note that DDOX uses [vibe.d](https://github.com/rejectedsoftware/vibe.d/), which currently by default uses libevent as its core. Please follow its installation instructions, too, if necessary.

Filtering docs
--------------

You can filter the JSON file using `ddox filter <path_to_json>`.

The following command will filter out all modules starting with "core.sync.", except those starting with "core.sync.mutex" or "core.sync.condition". `--in` always takes precedence over `--ex` here. Additionally, all members with a protection lower than public will be filtered out.

	./ddox filter path/to/docs.json --ex core.sync. --in core.sync.mutex --in core.sync.condition --min-protection Public


Serving the docs on localhost
-----------------------------

Ensure your current working directory contains ddox's directory "public", or a modified version of it (otherwise the CSS stylings and JavaScript extras won't work).

	cd path/to/ddox

Then, simply run the following command and go to <http://127.0.0.1:8080/>

	./ddox serve-html path/to/docs.json

Generating offline documentation
--------------------------------

The following commands will generate HTML docs (along with the default CSS stylings and JavaScript extras) in the folder "destination/path/public":

	cp -r path/to/ddox/public destination/path
	./ddox generate-html path/to/docs.json destination/path/public


Built-in support in DUB
-----------------------

Documentation for DUB projects can be built as simple as by running the following command within the project's directory:

	dub build -b ddox

The `"-ddoxFilterArgs"` field in `dub.json` (resp. `x:ddoxFilterArgs` in `dub.sdl`) can be used to customize the included contents.

Quickly serving the documentation on a local HTTP server, which is usually faster than writing out all HTML files to disk, is also possible:

	dub run -b ddox


DDOX specific Ddoc macros
-------------------------

Apart from the standard set of predefined macros, DDOX defines a macro `DDOX_ROOT_DIR`, which contains the relative path to the root of the documentation hierarchy (ending with a slash). It can be used to link to resources that reside in a fixed location within the same directory tree.


Known issues
------------

There are a number of issues due to limitations of the JSON output that DMD generates:

- User defined attributes don't show up in the documentation (issue #6)
- Declarations within `static if` are not shown (issues #19 and #86)
- Modules without a documented module declaration are omitted (issues #164 and #10)
- Some declarations with complex types may fail to parse and will be missing proper cross linking
