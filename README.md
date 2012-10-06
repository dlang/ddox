= DDocX documentation engine =

== First steps ==

1. Download and install vibe.d
2. Generate JSON for your project by adding the command line switches "-D -X -Xfdocs.json" to your DMD command line
3. Got to the ddox directory and run "vibe -- serve-html <path-to-your-docs.json>"
4. Open http://127.0.0.1:8080/ in your browser