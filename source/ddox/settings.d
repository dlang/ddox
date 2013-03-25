/**
	Contains definitions for customizing DDOX behavior.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.settings;

import vibe.inet.url;

enum SortMode {
	none,
	name,
	protectionName,

	None = none,
	Name = name
}

enum NavigationType {
	moduleList,
	moduleTree,
	declarationTree,

	ModuleList = moduleList,
	ModuleTree = moduleTree,
	DeclarationTree = declarationTree,
}

class DdoxSettings {
	NavigationType navigationType = NavigationType.moduleTree;
	SortMode moduleSort = SortMode.protectionName;
	SortMode declSort = SortMode.protectionName;
	string[] packageOrder;
	bool inheritDocumentation = true;
	bool mergeEponymousTemplates = true;
	bool oldJsonFormat; // DMD <= 2.061
}


class GeneratorSettings {
	NavigationType navigationType = NavigationType.moduleTree;
	// used for sitemap generation and for determining the URL prefix in registerApiDocs()
	Url siteUrl = Url.parse("http://localhost:8080/");
}

