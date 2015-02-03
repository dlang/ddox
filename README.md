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

1. Install [dub](https://github.com/rejectedsoftware/dub/)
2. Generate JSON for your project by adding the command line switches `-D -X -Xfdocs.json` to your DMD command line (Note that you may need to clean up all the generated .html files afterwards)
3. Check out ddox and run `dub build` from its root folder


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

