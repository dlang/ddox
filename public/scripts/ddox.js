function setupDdox()
{
	$(".tree-view").children(".package").click(toggleTree);
	$(".tree-view.collapsed").children("ul").hide();
}

function toggleTree()
{
	node = $(this).parent();
	node.toggleClass("collapsed");
	if( node.hasClass("collapsed") ){
		node.children("ul").hide();
	} else {
		node.children("ul").show();
	}
	return false;
}

var searchCounter = 0;
var lastSearchString = "";

function performSymbolSearch()
{
	var searchstring = $("#symbolSearch").val().toLowerCase();

	if (searchstring == lastSearchString) return;
	lastSearchString = searchstring;

	var scnt = ++searchCounter;
	$('#symbolSearchResults').empty();

	var terms = $.trim(searchstring).split(/\s+/);
	if (terms.length == 0 || (terms.length == 1 && terms[0].length < 2)) return;

	var results = [];
	for (i in symbols) {
		var sym = symbols[i];
		var all_match = true;
		for (j in terms)
			if (sym.name.toLowerCase().indexOf(terms[j]) < 0) {
				all_match = false;
				break;
			}
		if (!all_match) continue;

		results.push(sym);
	}

	function compare(a, b) {
		var adep = a.attributes.indexOf("deprecated") >= 0;
		var bdep = b.attributes.indexOf("deprecated") >= 0;
		if (adep != bdep) return adep - bdep;

		var aname = a.name.toLowerCase();
		var bname = b.name.toLowerCase();

		var alen = aname.split(".").length;
		var blen = bname.split(".").length;
		if (alen < blen) return -1;
		if (alen > blen) return 1;

		if (aname < bname) return -1;
		if (aname > bname) return 1;
		return 0;
	}

	results.sort(compare);

	for (i = 0; i < results.length && i < 100; i++) {
			var sym = results[i];

			var el = $(document.createElement("li"));
			el.addClass(sym.kind);
			for (j in sym.attributes)
				el.addClass(sym.attributes[j]);
			//var lidx = sym.name.lastIndexOf(".");
			//var name = lidx >= 0 ? sym.name.substr(lidx+1) : sym.name;
			var name = sym.name;
			el.append('<a href="'+symbolSearchRootDir+sym.path+'" title="'+name+'">'+name+'</a>');
			$('#symbolSearchResults').append(el);
		}

	if (results.length > 100) {
		$('#symbolSearchResults').append("<li>&hellip;"+(results.length-100)+" additional results</li>");
	}
}
