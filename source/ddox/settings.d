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
	protectionInheritanceName,

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
	SortMode declSort = SortMode.protectionInheritanceName;
	string[] packageOrder;
	bool inheritDocumentation = true;
	bool mergeEponymousTemplates = true;
	bool oldJsonFormat; // DMD <= 2.061
}


class GeneratorSettings {
	NavigationType navigationType = NavigationType.moduleTree;
	/// used for sitemap generation and for determining the URL prefix in registerApiDocs()
	URL siteUrl = URL("http://localhost:8080/");
	/// focus search field on load
	bool focusSearchField = false;
	/// enable JS keyboard navigation
	bool enableKeyNavigation = true;
	/// Use only lower case file names and aggregate matching entities (useful for case insensitive file systems)
	bool lowerCaseNames = false;
}

