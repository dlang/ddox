DDocX documentation engine
==========================

First steps
-----------

1. Download and install [vibe.d](http://vibed.org/).
2. Generate JSON for your project by adding the command line switches `-D -X -Xfdocs.json` to your DMD command line. (Note that you may need to clean up all the generated .html files afterwards)
3. Build ddox by running `vibe build` from the ddocx folder.


Filtering docs
--------------

You can filter the JSON file using `./app filter`.

The following command will filter out all modules starting with "core.sync.", except those starting with "core.sync.mutex" or "core.sync.condition". `--in` always takes precedence over `--ex` here. Additionally, all members with a protection lower than public will be filtered out.

	app filter docs.json --ex core.sync. --in core.sync.mutex --in core.sync.condition --min-protection Public


Serving the docs on localhost
-----------------------------

Simply run the following command and go to <http://127.0.0.1:8080/>

	app serve-html docs.json

Generating offline documentation
--------------------------------

The following command will generate HTML docs in the folder "docs":

	app generate-html docs.json docs
