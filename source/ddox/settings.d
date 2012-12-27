/**
	Contains definitions for customizing DDOX behavior.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.settings;

import vibe.inet.url;

enum SortMode {
	None,
	Name
}

enum NavigationType {
	ModuleList,
	ModuleTree,
	DeclarationTree,
}

class DdoxSettings {
	NavigationType navigationType = NavigationType.ModuleTree;
	SortMode moduleSort = SortMode.Name;
	SortMode declSort = SortMode.None;
	bool inheritDocumentation = true;
	bool mergeEponymousTemplates = true;
}


class GeneratorSettings {
	NavigationType navigationType = NavigationType.ModuleTree;
	// used for sitemap generation and for determining the URL prefix in registerApiDocs()
	Url siteUrl = Url.parse("http://localhost:8080/");
}

