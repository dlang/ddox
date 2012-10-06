module ddox.ddox;



enum SortMode {
	None,
	Name
}

class DdoxSettings {
	bool moduleNavAsTree = false;
	SortMode moduleSort = SortMode.Name;
	SortMode declSort = SortMode.None;
	bool inheritDocumentation = true;
	string[] excludedPaths;
	string[] includedPaths;
}

