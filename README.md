DDOX documentation engine
==========================

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

Simply run the following command and go to <http://127.0.0.1:8080/>

	./ddox serve-html path/to/docs.json

Generating offline documentation
--------------------------------

The following command will generate HTML docs in the folder "docs":

	./ddox generate-html path/to/docs.json destination/path
