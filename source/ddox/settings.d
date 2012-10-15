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

class DdoxSettings {
	bool moduleNavAsTree = false;
	SortMode moduleSort = SortMode.Name;
	SortMode declSort = SortMode.None;
	bool inheritDocumentation = true;
	bool mergeEponymousTemplates = true;
}


class GeneratorSettings {
	bool navPackageTree = true;
}

