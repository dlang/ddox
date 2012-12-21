/**
	DietDoc/DDOC support routines

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.ddoc;

import vibe.core.log;
import vibe.utils.string;

import std.algorithm : map, min;
import std.array;
import std.conv;
import std.string;


/**
	Takes a DDOC string and outputs formatted HTML.

	The hlevel parameter specifies the header level used for section names (&lt;h2&gt by default).
	By specifying a display_section callback it is also possible to output only certain sections.
*/
string formatDdocComment(string ddoc_, int hlevel = 2, bool delegate(string) display_section = null)
{
	return formatDdocComment(new BareContext(ddoc_), hlevel, display_section);
}
/// ditto
string formatDdocComment(DdocContext context, int hlevel = 2, bool delegate(string) display_section = null)
{
	auto dst = appender!string();
	filterDdocComment(dst, context, hlevel, display_section);
	return dst.data;
}
/// ditto
void filterDdocComment(R)(ref R dst, DdocContext context, int hlevel = 2, bool delegate(string) display_section = null)
{
	auto lines = splitLines(context.docText);
	if( !lines.length ) return;

	string[string] macros;
	parseMacros(macros, s_standardMacros);
	parseMacros(macros, s_defaultMacros);
	parseMacros(macros, context.defaultMacroDefinitions);

	int getLineType(int i)
	{
		auto ln = strip(lines[i]);
		if( ln.length == 0 ) return BLANK;
		else if( ln.length >= 3 && ln.allOf("-") ) return CODE;
		else if( ln.indexOf(':') > 0 && !ln[0 .. ln.indexOf(':')].anyOf(" \t") ) return SECTION;
		return TEXT;
	}

	int skipCodeBlock(int start)
	{
		do {
			start++;
		} while(start < lines.length && getLineType(start) != CODE);
		return start+1;
	}

	int skipSection(int start)
	{
		while(start < lines.length ){
			if( getLineType(start) == SECTION ){
				auto cidx = std.string.indexOf(lines[start], ':');
				// FIXME: should this be if( !lines[start][0 .. cidx].anyOf(" \t") && ... ) ?
				if( !lines[start][cidx .. $].startsWith("://") )
					break;
			}
			if( getLineType(start) == CODE )
				start = skipCodeBlock(start);
			else start++;
		}
		return start;
	}

	int skipBlock(int start)
	{
		do {
			start++;
		} while(start < lines.length && getLineType(start) == TEXT);
		return start;
	}


	int i = 0;

	Section[] sections;

	// special case short description on the first line
	while( i < lines.length && getLineType(i) == BLANK ) i++;
	if( i < lines.length && getLineType(i) == TEXT ){
		auto j = skipBlock(i);
		sections ~= Section("$Short", lines[i .. j].map!(l => l.strip()).join(" "));
		i = j;
	}

	// first section is implicitly the long description
	{
		auto j = skipSection(i);
		if( j > i ) sections ~= Section("$Long", lines[i .. j]);
		i = j;
	}

	// parse all other sections
	while( i < lines.length ){
		assert(getLineType(i) == SECTION);
		auto j = skipSection(i+1);
		auto pidx = lines[i].indexOf(':');
		auto sect = strip(lines[i][0 .. pidx]);
		lines[i] = strip(lines[i][pidx+1 .. $]);
		if( lines[i].empty ) i++;
		if( sect == "Macros" ) parseMacros(macros, lines[i .. j]);
		else sections ~= Section(sect, lines[i .. j]);
		i = j;
	}

	parseMacros(macros, s_overrideMacros);
	parseMacros(macros, context.overrideMacroDefinitions);

	foreach( s; sections ){
		if( display_section && !display_section(s.name) ) continue;
		if( s.name == "$Short") renderTextLine(dst, s.lines[0], context, macros);
		else parseSection(dst, s.name, s.lines, context, hlevel, macros);
	}
}


/**
	Sets a set of macros that will be available to all calls to formatDdocComment.
*/
void setDefaultDdocMacroFile(string filename)
{
	import vibe.core.file;
	import vibe.stream.stream;
	auto text = readAllUtf8(openFile(filename));
	s_defaultMacros = splitLines(text);
}


/**
	Sets a set of macros that will be available to all calls to formatDdocComment and override local macro definitions.
*/
void setOverrideDdocMacroFile(string filename)
{
	import vibe.core.file;
	import vibe.stream.stream;
	auto text = readAllUtf8(openFile(filename));
	s_overrideMacros = splitLines(text);
}


/**
	Provides context information about the documented element.
*/
interface DdocContext {
	/// The DDOC text
	@property string docText();

	/// A line array with macro definitions
	@property string[] defaultMacroDefinitions();

	/// Line array with macro definitions that take precedence over local macros
	@property string[] overrideMacroDefinitions();

	/// Looks up a symbol in the scope of the documented element and returns a link to it.
	string lookupScopeSymbolLink(string name);
}

private class BareContext : DdocContext {
	private string m_ddoc;
	
	this(string ddoc)
	{
		m_ddoc = ddoc;
	}

	@property string docText() { return m_ddoc; }
	@property string[] defaultMacroDefinitions() { return null; }
	@property string[] overrideMacroDefinitions() { return null; }
	string lookupScopeSymbolLink(string name) { return null; }
}

private enum {
	BLANK,
	TEXT,
	CODE,
	SECTION
}

private struct Section {
	string name;
	string[] lines;

	this(string name, string[] lines...)
	{
		this.name = name;
		this.lines = lines;
	}
}

private {
	string[] s_defaultMacros;
	string[] s_overrideMacros;
}

/// private
private void parseSection(R)(ref R dst, string sect, string[] lines, DdocContext context, int hlevel, string[string] macros)
{
	void putHeader(string hdr){
		if( hlevel <= 0 ) return;
		dst.put("<section>");
		if( sect.length > 0 && sect[0] != '$' ){
			dst.put("<h"~to!string(hlevel)~">");
			foreach( ch; hdr ) dst.put(ch == '_' ? ' ' : ch);
			dst.put("</h"~to!string(hlevel)~">\n");
		}
	}

	void putFooter(){
		if( hlevel <= 0 ) return;
		dst.put("</section>\n");
	}

	int getLineType(int i)
	{
		auto ln = strip(lines[i]);
		if( ln.length == 0 ) return BLANK;
		else if( ln.length >= 3 &&ln.allOf("-") ) return CODE;
		else if( ln.indexOf(':') > 0 && !ln[0 .. ln.indexOf(':')].anyOf(" \t") ) return SECTION;
		return TEXT;
	}

	int skipBlock(int start)
	{
		do {
			start++;
		} while(start < lines.length && getLineType(start) == TEXT);
		return start;
	}

	// run all macros first
	auto tmpdst = appender!string();
	renderTextLine(tmpdst, lines.join("\n"), context, macros);
	lines = splitLines(tmpdst.data);

	int skipCodeBlock(int start)
	{
		do {
			start++;
		} while(start < lines.length && getLineType(start) != CODE);
		return start;
	}

	switch( sect ){
		default:
			putHeader(sect);
			int i = 0;
			while( i < lines.length ){
				int lntype = getLineType(i);

				if( lntype == BLANK ){ i++; continue; }

				switch( lntype ){
					default: assert(false, "Unexpected line type "~to!string(lntype)~": "~lines[i]);
					case SECTION:
					case TEXT:
						bool p = lines.length > 1 || hlevel >= 1;
						if( p ) dst.put("<p>");
						auto j = skipBlock(i);
						bool first = true;
						foreach( ln; lines[i .. j] ){
							if( !first ) dst.put(' ');
							dst.put(ln.strip());
						}
						if( p ) dst.put("</p>\n");
						i = j;
						break;
					case CODE:
						dst.put("<pre class=\"code prettyprint\">");
						auto j = skipCodeBlock(i);
						auto base_indent = baseIndent(lines[i+1 .. j]);
						foreach( ln; lines[i+1 .. j] ){
							dst.put(ln.unindent(base_indent));
							dst.put("\n");
						}
						dst.put("</pre>\n");
						i = j+1;
						break;
				}
			}
			putFooter();
			break;
		case "Params":
			putHeader("Parameters");
			dst.put("<table><col class=\"caption\"><tr><th>Parameter name</th><th>Description</th></tr>\n");
			bool in_dt = false;
			foreach( ln; lines ){
				auto eidx = ln.indexOf("=");
				if( eidx < 0 ){
					if( in_dt ){
						dst.put(' ');
						dst.put(ln.strip());
					} else if( ln.strip().length ) logWarn("Out of place text in param section: %s", ln.strip());
				} else {
					auto pname = ln[0 .. eidx].strip();
					auto pdesc = ln[eidx+1 .. $].strip();
					if( in_dt ) dst.put("</td></tr>\n");
					dst.put("<tr><td><a id=\"");
					dst.put(pname);
					dst.put("\"></a>");
					dst.put(pname);
					dst.put("</td><td>\n");
					dst.put(pdesc);
					in_dt = true;
				}
			}
			if( in_dt ) dst.put("</td>\n");
			dst.put("</tr></table>\n");
			putFooter();
			break;
	}

}

/// private
private void renderTextLine(R)(ref R dst, string line, DdocContext context, string[string] macros, string[] params = null)
{
	while( line.length > 0 ){
		switch( line[0] ){
			default:
				dst.put(line[0]);
				line = line[1 .. $];
				break;
			case '_':
				line = line[1 .. $];
				auto ident = skipIdent(line);
				if( ident.length ) dst.put(ident);
				else dst.put('_');
				break;
			case 'a': .. case 'z':
			case 'A': .. case 'Z':
				assert(line[0] >= 'a' && line[0] <= 'z' || line[0] >= 'A' && line[0] <= 'Z');
				auto ident = skipIdent(line);
				auto link = context.lookupScopeSymbolLink(ident);
				if( link.length ){
					dst.put("<a href=\"");
					dst.put(link);
					dst.put("\"><code class=\"prettyprint lang-d\">");
					dst.put(ident);
					dst.put("</code></a>");
				} else dst.put(ident);
				break;
			case '$':
				renderMacro(dst, line, context, macros, params);
				break;
		}
	}
}

/// private
private void renderMacro(R)(ref R dst, ref string line, DdocContext context, string[string] macros, string[] params = null)
{
	line = line[1 .. $];
	if( line.length < 1) return;

	if( line[0] >= '0' && line[0] <= '9' ){
		int pidx = line[0]-'0';
		if( pidx < params.length )
			dst.put(strip(params[pidx]));
		line = line[1 .. $];
	} else if( line[0] == '+' ){
		if( params.length ){
			auto idx = params[0].indexOf(',');
			if( idx >= 0 ) dst.put(params[0][idx+1 .. $]);
		}
		line = line[1 .. $];
	} else if( line[0] == '(' ){
		line = line[1 .. $];
		int l = 1;
		size_t cidx = 0;
		for( cidx = 0; cidx < line.length && l > 0; cidx++ ){
			if( line[cidx] == '(' ) l++;
			else if( line[cidx] == ')' ) l--;
		}
		if( l > 0 ){
			logDebug("Unmatched parenthesis in DDOC comment: %s", line[0 .. cidx]);
			return;
		}
		if( cidx < 1 ){
			logDebug("Empty macro parens.");
			return;
		}

		auto mnameidx = line[0 .. cidx-1].countUntilAny(" \t\r\n");
		if( mnameidx < 0 ) mnameidx = cidx-1;
		if( mnameidx == 0 ){
			logDebug("Macro call in DDOC comment is missing macro name.");
			return;
		}
		auto mname = line[0 .. mnameidx];

		string[] args;
		if( mnameidx+1 < cidx ){
			auto rawargs = splitParams(line[mnameidx+1 .. cidx-1]);
			foreach( arg; rawargs ){
				auto argtext = appender!string();
				renderTextLine(argtext, arg, context, macros, params);
				args ~= argtext.data();
			}
		}
		args = join(args, ",") ~ args;

		logTrace("PARAMS for %s: %s", mname, args);
		line = line[cidx .. $];

		if( auto pm = mname in macros ){
			logTrace("MACRO %s: %s", mname, *pm);
			renderTextLine(dst, *pm, context, macros, args);
		} else {
			logTrace("Macro '%s' not found.", mname);
			if( args.length ) dst.put(args[0]);
		}
	}
}

private string[] splitParams(string ln)
{
	string[] ret;
	size_t i = 0, start = 0;
	while(i < ln.length){
		if( ln[i] == ',' ){
			ret ~= ln[start .. i];
			start = ++i;
		} else if( ln[i] == '(' ){
			i++;
			int l = 1;
			for( ; i < ln.length && l > 0; i++ ){
				if( ln[i] == '(' ) l++;
				else if( ln[i] == ')' ) l--;
			}
		} else i++;
	}
	if( i > start ) ret ~= ln[start .. i];
	return ret;
}

private string skipWhitespace(ref string ln)
{
	string ret = ln;
	while( ln.length > 0 ){
		if( ln[0] == ' ' || ln[0] == '\t' )
			break;
		ln = ln[1 .. $];
	}
	return ret[0 .. ret.length - ln.length];
}

private string skipIdent(ref string str)
{
	size_t i = 0;
	bool last_was_ident = false;
	while( i < str.length ){
		// dots are allowed if surrounded by identifiers
		if( last_was_ident && str[i] == '.' ){
			last_was_ident = false;
			i++;
			continue;
		}
		if( str[i] != '_' && (str[i] < 'a' || str[i] > 'z') && (str[i] < 'A' || str[i] > 'Z') && (str[i] < '0' || str[i] > '9') )
			break;
		last_was_ident = true;
		i++;
	}
	if( i > 0 && str[i-1] == '.' ) i--;
	auto ret = str[0 .. i];
	str = str[i .. $];
	return ret;
}

private void parseMacros(ref string[string] macros, in string[] lines)
{
	string lastname;
	foreach( ln; lines ){
		auto pidx = ln.indexOf('=');
		string name;
		if( pidx > 0 ){
			name = ln[0 .. pidx].strip();
			bool badname = false;
			foreach( ch; name ){
				if( ch >= 'A' && ch <= 'Z' ) continue;
				if( ch >= '0' && ch <= 'Z' ) continue;
				if( ch == '_' ) continue;
				name = null;
				break;
			}
		}

		if( name.length ){
			string value = strip(ln[pidx+1 .. $]);
			macros[name] = value;
			lastname = name;
		} else if( lastname.length ){
			macros[lastname] ~= "\n" ~ strip(ln);
		}
	}
}

private int baseIndent(string[] lines)
{
	if( lines.length == 0 ) return 0;
	int ret = int.max;
	foreach( ln; lines ){
		int i = 0;
		while( i < ln.length && (ln[i] == ' ' || ln[i] == '\t') )
			i++;
		if( i < ln.length ) ret = min(ret, i); 
	}
	return ret;
}

private string unindent(string ln, int amount)
{
	while( amount > 0 && ln.length > 0 && (ln[0] == ' ' || ln[0] == '\t') )
		ln = ln[1 .. $], amount--;
	return ln;
}

private immutable s_standardMacros = [
	"P = <p>$0</p>",
	"DL = <dl>$0</dl>",
	"DT = <dt>$0</dt>",
	"DD = <dd>$0</dd>",
	"TABLE = <table>$0</table>",
	"TR = <tr>$0</tr>",
	"TH = <th>$0</th>",
	"TD = <td>$0</td>",
	"OL = <ol>$0</ol>",
	"UL = <ul>$0</ul>",
	"LI = <li>$0</li>",
	"LINK = <a href=\"$0\">$0</a>",
	"LINK2 = <a href=\"$1\">$+</a>",
	"LPAREN= (",
	"RPAREN= )"
];
