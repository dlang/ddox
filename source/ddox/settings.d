/**
	Contains definitions for customizing DDOX behavior.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.settings;


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
}

