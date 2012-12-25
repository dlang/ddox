/**
	DietDoc/DDOC support routines

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.ddoc;

import vibe.core.log;
import vibe.utils.string;

import std.algorithm : countUntil, map, min, remove;
import std.array;
import std.conv;
import std.string;
import std.uni : isAlpha;


static this()
{
	s_standardMacros = [
		"P" : "<p>$0</p>",
		"DL" : "<dl>$0</dl>",
		"DT" : "<dt>$0</dt>",
		"DD" : "<dd>$0</dd>",
		"TABLE" : "<table>$0</table>",
		"TR" : "<tr>$0</tr>",
		"TH" : "<th>$0</th>",
		"TD" : "<td>$0</td>",
		"OL" : "<ol>$0</ol>",
		"UL" : "<ul>$0</ul>",
		"LI" : "<li>$0</li>",
		"LINK" : "<a href=\"$0\">$0</a>",
		"LINK2" : "<a href=\"$1\">$+</a>",
		"LPAREN" : "(",
		"RPAREN" : ")"
	];
}


/**
	Takes a DDOC string and outputs formatted HTML.

	The hlevel parameter specifies the header level used for section names (&lt;h2&gt by default).
	By specifying a display_section callback it is also possible to output only certain sections.
*/
string formatDdocComment(string ddoc_, int hlevel = 2, bool delegate(string) display_section = null)
{
	return formatDdocComment(ddoc_, new BareContext, hlevel, display_section);
}
/// ditto
string formatDdocComment(string text, DdocContext context, int hlevel = 2, bool delegate(string) display_section = null)
{
	auto dst = appender!string();
	filterDdocComment(dst, text, context, hlevel, display_section);
	return dst.data;
}
/// ditto
void filterDdocComment(R)(ref R dst, string text, DdocContext context, int hlevel = 2, bool delegate(string) display_section = null)
{
	auto comment = new DdocComment(text);
	comment.renderSectionsR(dst, context, display_section, hlevel);
}


/**
	Sets a set of macros that will be available to all calls to formatDdocComment.
*/
void setDefaultDdocMacroFile(string filename)
{
	import vibe.core.file;
	import vibe.stream.stream;
	auto text = readAllUtf8(openFile(filename));
	s_defaultMacros = null;
	parseMacros(s_defaultMacros, splitLines(text));
}


/**
	Sets a set of macros that will be available to all calls to formatDdocComment and override local macro definitions.
*/
void setOverrideDdocMacroFile(string filename)
{
	import vibe.core.file;
	import vibe.stream.stream;
	auto text = readAllUtf8(openFile(filename));
	s_overrideMacros = null;
	parseMacros(s_overrideMacros, splitLines(text));
}


/**
	Holds a DDOC comment and formats it sectionwise as HTML.
*/
class DdocComment {
	private {
		Section[string] m_sections;
		string[] m_sectionNames;
		string[string] m_macros;
		bool m_isDitto = false;
		bool m_isPrivate = false;
	}

	this(string text)
	{
		text = text.strip();

		if( icmp(text, "ditto") == 0 ){ m_isDitto = true; return; }
		if( icmp(text, "private") == 0 ){ m_isPrivate = true; return; }


//		parseMacros(m_macros, context.defaultMacroDefinitions);

		auto lines = splitLines(text);
		if( !lines.length ) return;

		int getLineType(int i)
		{
			auto ln = strip(lines[i]);
			if( ln.length == 0 ) return BLANK;
			else if( ln.length >= 3 && ln.allOf("-") ) return CODE;
			else if( ln.indexOf(':') > 0 && isIdent(ln[0 .. ln.indexOf(':')]) ) return SECTION;
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
				if( getLineType(start) == SECTION ) break;
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

		// special case short description on the first line
		while( i < lines.length && getLineType(i) == BLANK ) i++;
		if( i < lines.length && getLineType(i) == TEXT ){
			auto j = skipBlock(i);
			m_sections["$Short"] = Section("$Short", lines[i .. j]);
			m_sectionNames ~= "$Short";
			i = j;
		}

		// first section is implicitly the long description
		{
			auto j = skipSection(i);
			if( j > i ){
				m_sections["$Long"] = Section("$Long", lines[i .. j]);
				m_sectionNames ~= "$Long";
				i = j;
			}
		}

		// parse all other sections
		while( i < lines.length ){
			assert(getLineType(i) == SECTION);
			auto j = skipSection(i+1);
			auto pidx = lines[i].indexOf(':');
			auto sect = strip(lines[i][0 .. pidx]);
			lines[i] = strip(lines[i][pidx+1 .. $]);
			if( lines[i].empty ) i++;
			if( sect == "Macros" ) parseMacros(m_macros, lines[i .. j]);
			else {
				m_sections[sect] = Section(sect, lines[i .. j]);
				m_sectionNames ~= sect;
			}
			i = j;
		}

//		parseMacros(m_macros, context.overrideMacroDefinitions);
	}

	@property bool isDitto() const { return m_isDitto; }
	@property bool isPrivate() const { return m_isPrivate; }

	bool hasSection(string name) const { return (name in m_sections) !is null; }

	void renderSectionR(R)(ref R dst, string name, int hlevel = 2)
	{
		auto sect = name in m_sections;
		if( !sect ) return null;

		parseSection(dst, name, s.lines, context, hlevel, m_macros);
	}

	void renderSectionsR(R)(ref R dst, DdocContext context, bool delegate(string) display_section, int hlevel)
	{
		foreach( i, s; m_sectionNames ){
			if( !display_section(s) ) continue;
			parseSection(dst, s, m_sections[s].lines, context, hlevel, m_macros);
		}
	}

	string renderSection(DdocContext context, string name, int hlevel = 2)
	{
		auto sect = name in m_sections;
		if( !sect ) return null;

		auto dst = appender!string();
		parseSection(dst, name, sect.lines, context, hlevel, m_macros);
		return dst.data;
	}

	string renderSections(DdocContext context, bool delegate(string) display_section, int hlevel)
	{
		auto dst = appender!string();
		renderSectionsR(dst, context, display_section, hlevel);
		return dst.data;
	}
}


/**
	Provides context information about the documented element.
*/
interface DdocContext {
	/// A line array with macro definitions
	@property string[] defaultMacroDefinitions();

	/// Line array with macro definitions that take precedence over local macros
	@property string[] overrideMacroDefinitions();

	/// Looks up a symbol in the scope of the documented element and returns a link to it.
	string lookupScopeSymbolLink(string name);
}


private class BareContext : DdocContext {
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
	string[string] s_standardMacros;
	string[string] s_defaultMacros;
	string[string] s_overrideMacros;
}

/// private
private void parseSection(R)(ref R dst, string sect, string[] lines, DdocContext context, int hlevel, string[string] macros)
{
	if( sect == "$Short" ) hlevel = -1;

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
	{
		//logTrace("MACROS for section %s: %s", sect, macros.keys);
		auto tmpdst = appender!string();
		auto text = lines.join("\n");
		renderMacros(tmpdst, text, context, macros);
		lines = splitLines(tmpdst.data);
	}

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
						if( hlevel >= 0 ) dst.put("<p>");
						auto j = skipBlock(i);
						bool first = true;
						foreach( ln; lines[i .. j] ){
							if( !first ) dst.put(' ');
							else first = false;
							renderTextLine(dst, ln.strip(), context);
						}
						if( hlevel >= 0 ) dst.put("</p>\n");
						i = j;
						break;
					case CODE:
						dst.put("<pre class=\"code prettyprint\">");
						auto j = skipCodeBlock(i);
						auto base_indent = baseIndent(lines[i+1 .. j]);
						foreach( ln; lines[i+1 .. j] ){
							renderCodeLine(dst, ln.unindent(base_indent), context);
							dst.put('\n');
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
			dst.put("<table><col class=\"caption\"><tr><th>Name</th><th>Description</th></tr>\n");
			bool in_parameter = false;
			string desc;
			foreach( string ln; lines ){
				// check if the line starts a parameter documentation
				string name;
				auto eidx = ln.indexOf("=");
				if( eidx > 0 ) name = ln[0 .. eidx].strip();
				if( !isIdent(name) ) name = null;

				// if it does, start a new row
				if( name.length ){
					if( in_parameter ){
						renderTextLine(dst, desc, context);
						dst.put("</td></tr>\n");
					}

					dst.put("<tr><td id=\"");
					dst.put(name);
					dst.put("\">");
					dst.put(name);
					dst.put("</td><td>");

					desc = ln[eidx+1 .. $];
					in_parameter = true;
				} else if( in_parameter ) desc ~= "\n" ~ ln;
			}

			if( in_parameter ){
				renderTextLine(dst, desc, context);
				dst.put("</td></tr>\n");
			}

			dst.put("</table>\n");
			putFooter();
			break;
	}

}

/// private
private void renderTextLine(R)(ref R dst, string line, DdocContext context)
{
	while( line.length > 0 ){
		switch( line[0] ){
			default:
				dst.put(line[0]);
				line = line[1 .. $];
				break;
			case '<':
				dst.put(skipHtmlTag(line));
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
					if( link != "#" ){
						dst.put("<a href=\"");
						dst.put(link);
						dst.put("\">");
					}
					dst.put("<code class=\"prettyprint lang-d\">");
					dst.put(ident);
					dst.put("</code>");
					if( link != "#" ) dst.put("</a>");
				} else dst.put(ident.replace("._", "."));
				break;
		}
	}
}

/// private
private void renderCodeLine(R)(ref R dst, string line, DdocContext context)
{
	while( line.length > 0 ){
		switch( line[0] ){
			default:
				dst.put(line[0]);
				line = line[1 .. $];
				break;
			case 'a': .. case 'z':
			case 'A': .. case 'Z':
				assert(line[0] >= 'a' && line[0] <= 'z' || line[0] >= 'A' && line[0] <= 'Z');
				auto ident = skipIdent(line);
				auto link = context.lookupScopeSymbolLink(ident);
				if( link.length && link != "#" ){
					dst.put("<a href=\"");
					dst.put(link);
					dst.put("\">");
					dst.put(ident);
					dst.put("</a>");
				} else dst.put(ident);
				break;
		}
	}
}

/// private
private void renderMacros(R)(ref R dst, string line, DdocContext context, string[string] macros, string[] params = null)
{
	while( !line.empty ){
		auto idx = line.indexOf('$');
		if( idx < 0 ){
			dst.put(line);
			return;
		}
		dst.put(line[0 .. idx]);
		line = line[idx .. $];
		renderMacro(dst, line, context, macros, params);
	}
}

/// private
private void renderMacro(R)(ref R dst, ref string line, DdocContext context, string[string] macros, string[] params = null)
{
	assert(line[0] == '$');
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
				renderMacros(argtext, arg, context, macros, params);
				args ~= argtext.data();
			}
		}
		args = join(args, ",") ~ args;

		logTrace("PARAMS for %s: %s", mname, args);
		line = line[cidx .. $];

		auto pm = mname in s_overrideMacros;
		if( !pm ) pm = mname in macros;
		if( !pm ) pm = mname in s_defaultMacros;
		if( !pm ) pm = mname in s_standardMacros;

		if( pm ){
			logTrace("MACRO %s: %s", mname, *pm);
			renderMacros(dst, *pm, context, macros, args);
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

private string skipHtmlTag(ref string ln)
{
	assert(ln[0] == '<');

	// too short for a tag
	if( ln.length < 3 ) goto no_match;

	// skip HTML comment
	if( ln.startsWith("<!--") ){
		auto idx = ln[4 .. $].indexOf("-->");
		if( idx < 0 ) goto no_match;
		auto ret = ln[0 .. idx+7];
		ln = ln[ret.length .. $];
		return ret;
	}

	// skip over regular start/end tag
	if( ln[1].isAlpha() || ln[1] == '/' && ln[2].isAlpha() ){
		auto idx = ln.indexOf(">");
		if( idx < 0 ) goto no_match;
		auto ret = ln[0 .. idx+1];
		ln = ln[ret.length .. $];
		return ret;
	}

no_match:
	// found no match, return escaped '<'
	logTrace("Found stray '<' in DDOC string.");
	ln.popFront();
	return "$(LT)";
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
	string strcopy = str;

	bool last_was_ident = false;
	while( !str.empty ){
		auto ch = str.front;

		if( last_was_ident ){
			// dots are allowed if surrounded by identifiers
			if( ch == '.' ) last_was_ident = false;
			else if( ch != '_' && (ch < '0' || ch > '9') && !std.uni.isAlpha(ch) ) break;
		} else {
			if( ch != '_' && !std.uni.isAlpha(ch) ) break;
			last_was_ident = true;
		}
		str.popFront();
	}

	// if the identifier ended in a '.', remove it again
	if( str.length != strcopy.length && !last_was_ident )
		str = strcopy[strcopy.length-str.length-1 .. $];
	
	return strcopy[0 .. strcopy.length-str.length];
}

private bool isIdent(string str)
{
	skipIdent(str);
	return str.length == 0;
}

private void parseMacros(ref string[string] macros, in string[] lines)
{
	string name;
	foreach( string ln; lines ){
		if( !ln.strip().length ) continue;
		// macro definitions are of the form IDENT = ...
		auto pidx = ln.indexOf('=');
		if( pidx > 0 ){
			auto tmpnam = ln[0 .. pidx].strip();
			if( isIdent(tmpnam) ){
				// got new macro definition
				name = tmpnam;
				macros[name] = ln[pidx+1 .. $];
				continue;
			}
		}

		// append to previous macro definition, if any
		if( name.length ) macros[name] ~= "\n" ~ ln;
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
