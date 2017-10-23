/**
	Contains definitions for customizing DDOX behavior.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.settings;

import vibe.inet.url;
import diet.html : HTMLOutputStyle;
public import vibe.web.common : MethodStyle;

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
}


class GeneratorSettings {
	NavigationType navigationType = NavigationType.moduleTree;
	/// used for sitemap generation and for determining the URL prefix in registerApiDocs()
	URL siteUrl = URL("http://localhost:8080/");
	/// focus search field on load
	bool focusSearchField = false;
	/// Defines how symbol names are mapped to file names when generating file based documentation (useful for case insensitive file systems)
	MethodStyle fileNameStyle = MethodStyle.unaltered;
	/// Enables syntax highlighting for inline code
	bool highlightInlineCode = true;
	/// Select HTML style (e.g. compact, pretty)
	HTMLOutputStyle htmlOutputStyle = HTMLOutputStyle.pretty;

	/// Creates a page per enum member instead of putting everything into a single table.
	bool enumMemberPages;

	deprecated("Use fileNameStyle = MethodStyle.lowerCase instead.")
	@property bool lowerCase() const { return fileNameStyle == MethodStyle.lowerCase; }
	deprecated("Use fileNameStyle = MethodStyle.lowerCase instead.")
	@property void lowerCase(bool v) { fileNameStyle = MethodStyle.lowerCase; }
}
