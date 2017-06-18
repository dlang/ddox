/**
	DietDoc/DDOC support routines

	Copyright: © 2012-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.ddoc;

import vibe.core.log;
import vibe.utils.string;

import hyphenate : Hyphenator;

import std.algorithm : canFind, countUntil, map, min, remove;
import std.array;
import std.conv : to;
import std.string;
import std.uni : isAlpha;

// TODO: support escapes section


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
void setDefaultDdocMacroFiles(string[] filenames)
{
	import vibe.core.file;
	import vibe.stream.operations;
	s_defaultMacros = null;
	foreach (filename; filenames) {
		auto text = readAllUTF8(openFile(filename));
		parseMacros(s_defaultMacros, splitLines(text));
	}
}


/**
	Sets a set of macros that will be available to all calls to formatDdocComment and override local macro definitions.
*/
void setOverrideDdocMacroFiles(string[] filenames)
{
	import vibe.core.file;
	import vibe.stream.operations;
	s_overrideMacros = null;
	foreach (filename; filenames) {
		auto text = readAllUTF8(openFile(filename));
		parseMacros(s_overrideMacros, splitLines(text));
	}
}


/**
   Enable hyphenation of doc text.
*/
void enableHyphenation()
{
	s_hyphenator = Hyphenator(import("hyphen.tex")); // en-US
	s_enableHyphenation = true;
}


void hyphenate(R)(in char[] word, R orng)
{
	s_hyphenator.hyphenate(word, "\&shy;", s => orng.put(s));
}

/**
	Holds a DDOC comment and formats it sectionwise as HTML.
*/
class DdocComment {
	private {
		Section[] m_sections;
		string[string] m_macros;
		bool m_isDitto = false;
		bool m_isPrivate = false;
	}

	this(string text)
	{

		if (text.strip.icmp("ditto") == 0) { m_isDitto = true; return; }
		if (text.strip.icmp("private") == 0) { m_isPrivate = true; return; }

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
			if (start >= lines.length) return start; // unterminated code section
			return start+1;
		}

		int skipSection(int start)
		{
			while (start < lines.length) {
				if (getLineType(start) == SECTION) break;
				if (getLineType(start) == CODE)
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
			m_sections ~= Section("$Short", lines[i .. j]);
			i = j;
		}

		// first section is implicitly the long description
		{
			auto j = skipSection(i);
			if( j > i ){
				m_sections ~= Section("$Long", lines[i .. j]);
				i = j;
			}
		}

		// parse all other sections
		while( i < lines.length ){
			assert(getLineType(i) == SECTION);
			auto j = skipSection(i+1);
			assert(j <= lines.length);
			auto pidx = lines[i].indexOf(':');
			auto sect = strip(lines[i][0 .. pidx]);
			lines[i] = stripLeftDD(lines[i][pidx+1 .. $]);
			if (lines[i].empty && i < lines.length) i++;
			if (sect == "Macros") parseMacros(m_macros, lines[i .. j]);
			else {
				m_sections ~= Section(sect, lines[i .. j]);
			}
			i = j;
		}
	}

	@property bool isDitto() const { return m_isDitto; }
	@property bool isPrivate() const { return m_isPrivate; }

	/// The macros contained in the "Macros" section (if any)
	@property const(string[string]) macros() const { return m_macros; }

	bool hasSection(string name) const { return m_sections.canFind!(s => s.name == name); }

	void renderSectionR(R)(ref R dst, DdocContext context, string name, int hlevel = 2)
	{
		renderSectionsR(dst, context, s => s == name, hlevel);
	}

	void renderSectionsR(R)(ref R dst, DdocContext context, scope bool delegate(string) display_section, int hlevel)
	{
		string[string] allmacros;
		foreach (k, v; context.defaultMacroDefinitions) allmacros[k] = v;
		foreach (k, v; m_macros) allmacros[k] = v;
		foreach (k, v; context.overrideMacroDefinitions) allmacros[k] = v;

		foreach (s; m_sections) {
			if (display_section && !display_section(s.name)) continue;
			parseSection(dst, s.name, s.lines, context, hlevel, allmacros);
		}
	}

	string renderSection(DdocContext context, string name, int hlevel = 2)
	{
		auto dst = appender!string();
		renderSectionR(dst, context, name, hlevel);
		return dst.data;
	}

	string renderSections(DdocContext context, bool delegate(string) display_section, int hlevel)
	{
		auto dst = appender!string();
		renderSectionsR(dst, context, display_section, hlevel);
		return dst.data;
	}
}

enum DdocRenderOptions {
	defaults = highlightInlineCode,
	none = 0,

	highlightInlineCode = 1<<0,
}

/**
	Provides context information about the documented element.
*/
interface DdocContext {
	struct LinkInfo {
		string uri; // URI of the linked entity (usually a relative path)
		string shortName; // symbol name without qualified module name prefix
	}

	/// Returns a set of options to control the rendering process
	@property DdocRenderOptions renderOptions();

	/// A line array with macro definitions
	@property string[string] defaultMacroDefinitions();

	/// Line array with macro definitions that take precedence over local macros
	@property string[string] overrideMacroDefinitions();

	/// Looks up a symbol in the scope of the documented element and returns a link to it.
	LinkInfo lookupScopeSymbolLink(string name);
}


private class BareContext : DdocContext {
	@property DdocRenderOptions renderOptions() { return DdocRenderOptions.defaults; }
	@property string[string] defaultMacroDefinitions() { return null; }
	@property string[string] overrideMacroDefinitions() { return null; }
	LinkInfo lookupScopeSymbolLink(string name) { return LinkInfo(null, null); }
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
	immutable string[string] s_standardMacros;
	string[string] s_defaultMacros;
	string[string] s_overrideMacros;
	bool s_enableHyphenation;
	Hyphenator s_hyphenator;
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
		else if (ln.length >= 3 &&ln.allOf("-")) return CODE;
		return TEXT;
	}

	int skipBlock(int start)
	{
		do {
			start++;
		} while(start < lines.length && getLineType(start) == TEXT);
		return start;
	}

	int skipCodeBlock(int start)
	{
		do {
			start++;
		} while(start < lines.length && getLineType(start) != CODE);
		return start;
	}

	// handle backtick inline-code
	for (int i = 0; i < lines.length; i++) {
		int lntype = getLineType(i);
		if (lntype == CODE) i = skipCodeBlock(i);
		else if (sect == "Params") {
			auto idx = lines[i].indexOf('=');
			if (idx > 0 && isIdent(lines[i][0 .. idx].strip)) {
				lines[i] = lines[i][0 .. idx+1] ~ lines[i][idx+1 .. $].highlightAndCrossLink(context);
			} else {
				lines[i] = lines[i].highlightAndCrossLink(context);
			}
		} else lines[i] = lines[i].highlightAndCrossLink(context);
	}
	lines = renderMacros(lines.join("\n").stripDD, context, macros).splitLines();

	switch( sect ){
		default:
			putHeader(sect);
			int i = 0;
			while( i < lines.length ){
				int lntype = getLineType(i);

				switch( lntype ){
					default: assert(false, "Unexpected line type "~to!string(lntype)~": "~lines[i]);
					case BLANK:
						dst.put('\n');
						i++;
						continue;
					case TEXT:
						if( hlevel >= 0 ) dst.put("<p>");
						auto j = skipBlock(i);
						bool first = true;
						renderTextLine(dst, lines[i .. j].join("\n")/*.stripDD*/, context);
						dst.put('\n');
						if( hlevel >= 0 ) dst.put("</p>\n");
						i = j;
						break;
					case CODE:
						dst.put("<pre class=\"code\"><code class=\"lang-d\">");
						auto j = skipCodeBlock(i);
						auto base_indent = baseIndent(lines[i+1 .. j]);
						renderCodeLine(dst, lines[i+1 .. j].map!(ln => ln.unindent(base_indent)).join("\n"), context, true);
						dst.put("</code></pre>\n");
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

private string highlightAndCrossLink(string line, DdocContext context)
{
	auto dst = appender!string;
	highlightAndCrossLink(dst, line, context);
	return dst.data;
}

private void highlightAndCrossLink(R)(ref R dst, string line, DdocContext context)
{
	while (line.length > 0) {
		auto idx = line.indexOf('`');
		if (idx < 0) idx = line.length;

		foreach (el; HTMLTagStream(line[0 .. idx])) {
			if (el.isTag) {
				dst.put(el.text);
				continue;
			}

			highlightAndCrossLinkRaw(dst, el.text, context, el.inCode);
		}

		line = line[idx .. $];
		if (line.length) {
			auto idx2 = line[1 .. $].indexOf('`');
			if (idx2 < 0) { // a single backtick on a line is ignored and output normally
				dst.put('`');
				line = line[1 .. $];
			} else {
				dst.put("<code class=\"lang-d\">");
				dst.renderCodeLine(line[1 .. idx2+1], context, false);
				dst.put("</code>");
				line = line[min(idx2+2, $) .. $];
			}
		}
	}
}

private string highlightAndCrossLinkRaw(string line, DdocContext context, bool in_code)
{
	auto dst = appender!string;
	highlightAndCrossLinkRaw(dst, line, context, in_code);
	return dst.data;
}

private void highlightAndCrossLinkRaw(R)(ref R dst, string line, DdocContext context, bool in_code)
{
	import vibe.textfilter.html : filterHTMLAttribEscape, filterHTMLEscape;

	while (line.length > 0) {
		switch (line[0]) {
			default:
				dst.put(line[0]);
				line = line[1 .. $];
				break;
			case '_':
				line = line[1 .. $];
				auto ident = skipIdent(line);
				if( ident.length )
				{
					if (s_enableHyphenation && !in_code)
						hyphenate(ident, dst);
					else
						dst.put(ident);
				}
				else dst.put('_');
				break;
			case '.':
				if (line.length > 1 && (line[1 .. $].front.isAlpha || line[1] == '_')) goto case;
				else goto default;
			case 'a': .. case 'z':
			case 'A': .. case 'Z':

				auto url = skipUrl(line);
				if( url.length ){
					/*dst.put("<a href=\"");
					dst.put(url);
					dst.put("\">");*/
					dst.put(url);
					//dst.put("</a>");
					break;
				}

				auto ident = skipIdent(line);
				auto link = context.lookupScopeSymbolLink(ident);
				if (link.uri.length && in_code) {
					import ddox.highlight : highlightDCode;
					if (link.uri != "#") {
						dst.put("<a href=\"");
						dst.put(link.uri);
						if (link.shortName.length) {
							dst.put("\" title=\"");
							dst.filterHTMLAttribEscape(ident);
						}
						dst.put("\">");
					}
					auto dname = link.shortName.length ? link.shortName : ident;
					if (context.renderOptions & DdocRenderOptions.highlightInlineCode)
						dst.highlightDCode(dname, null);
					else
						dst.filterHTMLEscape(dname);

					if (link.uri != "#") dst.put("</a>");
				} else {
					ident = ident.replace("._", ".");
					if (s_enableHyphenation && !in_code)
						hyphenate(ident, dst);
					else
						dst.put(ident);
				}
				break;
		}
	}
}

/// private
private void renderTextLine(R)(ref R dst, string line, DdocContext context)
{
	foreach (el; HTMLTagStream(line)) {
		if (el.isTag) dst.put(el.text);
		else dst.htmlEscape(el.text);
	}
}

/// private
private void renderCodeLine(R)(ref R dst, string line, DdocContext context, bool in_code_section)
{
	import ddox.highlight : IdentifierRenderMode, highlightDCode;
	import vibe.textfilter.html : filterHTMLAttribEscape;
	if (in_code_section || context.renderOptions & DdocRenderOptions.highlightInlineCode) {
		dst.highlightDCode(line, (string ident, scope void delegate(IdentifierRenderMode, size_t) insert_ident) {
			auto link = context.lookupScopeSymbolLink(ident);
			auto nskip = link.shortName.length ? ident.count('.') - link.shortName.count('.') : 0;
			if (link.uri.length && link.uri != "#") {
				dst.put("<a href=\"");
				dst.put(link.uri);
				if (nskip > 0) {
					dst.put("\" title=\"");
					dst.filterHTMLAttribEscape(ident);
				}
				dst.put("\">");
				insert_ident(IdentifierRenderMode.nested, nskip);
				dst.put("</a>");
			} else insert_ident(IdentifierRenderMode.normal, 0);
		});
	} else {
		dst.highlightAndCrossLinkRaw(line, context, true);
	}
}

/// private
private void renderMacros(R)(ref R dst, string line, DdocContext context, string[string] macros, string[] params = null, MacroInvocation[] callstack = null, scope void delegate() flush_param_cb = null)
{
	while( !line.empty ){
		auto idx = line.indexOf('$');
		if( idx < 0 ){
			dst.put(line);
			return;
		}
		dst.put(line[0 .. idx]);
		line = line[idx .. $];
		renderMacro(dst, line, context, macros, params, callstack, flush_param_cb);
	}
}

/// private
private string renderMacros(string line, DdocContext context, string[string] macros, string[] params = null, MacroInvocation[] callstack = null, scope void delegate() flush_param_cb = null)
{
	auto app = appender!string;
	renderMacros(app, line, context, macros, params, callstack, flush_param_cb);
	return app.data;
}

/// private
private void renderMacro(R)(ref R dst, ref string line, DdocContext context, string[string] macros, string[] params, MacroInvocation[] callstack, scope void delegate() flush_param_cb = null)
{
	assert(line[0] == '$');
	line = line[1 .. $];
	if( line.length < 1) {
		dst.put("$");
		return;
	}

	if( line[0] >= '0' && line[0] <= '9' ){
		int pidx = line[0]-'0';
		if( pidx < params.length )
			dst.put(params[pidx]);
		line = line[1 .. $];
	} else if( line[0] == '+' ){
		if( params.length ){
			auto idx = params[0].indexOf(',');
			if( idx >= 0 ) {
				foreach (i, arg; splitParams(params[0][idx+1 .. $].specialStrip())) {
					if (i > 0 && flush_param_cb is null)
						dst.put(',');
					dst.put(arg);
					if (flush_param_cb !is null)
						flush_param_cb();
				}
			}
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
			dst.put("(");
			return;
		}
		if( cidx < 1 ){
			logDebug("Empty macro parens.");
			return;
		}

		auto mnameidx = line[0 .. cidx-1].countUntilAny(", \t\r\n");
		if( mnameidx < 0 ) mnameidx = cidx-1;
		if( mnameidx == 0 ){
			logDebug("Macro call in DDOC comment is missing macro name.");
			return;
		}

		auto mname = line[0 .. mnameidx];
		string rawargtext = line[mnameidx .. cidx-1];

		string[] args;
		if (rawargtext.length) {
			auto rawargs = splitParams(rawargtext);
			foreach (arg; rawargs) {
				auto argtext = appender!string();
				bool any = false;
				renderMacros(argtext, arg, context, macros, params, callstack, {
					args ~= argtext.data;
					argtext = appender!string();
					any = true;
				});
				if (!any || argtext.data.length) // always add at least one argument per raw argument
					args ~= argtext.data;
			}
		}
		if (args.length == 1 && args[0].specialStrip.length == 0) args = null; // remove a single empty argument

		args = join(args, ",").specialStrip() ~ args.map!(a => a.specialStrip).array;

		logTrace("PARAMS for %s: %s", mname, args);
		line = line[cidx .. $];

		// check for recursion termination conditions
		foreach_reverse (ref c; callstack) {
			if (c.name == mname && (args.length <= 1 || args == c.params)) {
				logTrace("Terminating recursive macro call of %s: %s", mname, params.length <= 1 ? "no argument text" : "same arguments as previous invocation");
				//line = line[cidx .. $];
				return;
			}
		}
		callstack.assumeSafeAppend();
		callstack ~= MacroInvocation(mname, args);


		const(string)* pm = mname in s_overrideMacros;
		if( !pm ) pm = mname in macros;
		if( !pm ) pm = mname in s_defaultMacros;
		if( !pm ) pm = mname in s_standardMacros;

		if (mname == "D") {
			auto tmp = appender!string;
			renderMacros(tmp, "$0", context, macros, args, callstack);
			dst.put("<code class=\"lang-d\">");
			foreach (el; HTMLTagStream(tmp.data)) {
				if (el.isTag) dst.put(el.text);
				else dst.renderCodeLine(el.text, context, false);
			}
			dst.put("</code>");
		} else if (mname == "DDOX_NAMED_REF") {
			auto sym = appender!string;
			renderMacros(sym, "$1", context, macros, args, callstack);

			auto link = sym.data.length > 0 && !sym.data.endsWith('.') ? context.lookupScopeSymbolLink(sym.data) : DdocContext.LinkInfo.init;
			if (link.uri.length) {
				dst.put(`<a href="`);
				dst.put(link.uri);
				dst.put(`" title="`);
				dst.put(sym.data);
				dst.put(`">`);
			}
			dst.renderMacros("$+", context, macros, args, callstack);			
			if (link.uri.length) dst.put("</a>");
		} else if (pm) {
			logTrace("MACRO %s: %s", mname, *pm);
			renderMacros(dst, *pm, context, macros, args, callstack);
		} else {
			logTrace("Macro '%s' not found.", mname);
			if( args.length ) dst.put(args[0]);
		}
	} else dst.put("$");
}

private struct MacroInvocation {
	string name;
	string[] params;
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

struct HTMLTagStream {
	private struct Element {
		string text;
		bool isTag;
		bool inCode;
	}

	private {
		string m_text;
		size_t m_endIndex;
		bool m_isTag;
		int m_inCode;
	}

	this(string text)
	{
		m_text = text;
		determineNextElement();
	}

	@property Element front() { return Element(m_text[0 .. m_endIndex], m_isTag, m_inCode > 0); }

	void popFront()
	{
		m_text = m_text[m_endIndex .. $];
		determineNextElement();
	}

	@property bool empty() const { return m_text.length == 0; }

	private void determineNextElement()
	{
		if (m_text.length == 0) return;

		// are we at a valid tag start?
		if (m_text[0] == '<') {
			auto tlen = getTagLength(m_text);
			if (tlen > 0) {
				m_isTag = true;
				m_endIndex = tlen;
				if (m_text.startsWith("<code ") || m_text[0 .. m_endIndex] == "<code>" ) ++m_inCode;
				else if (m_text[0 .. m_endIndex] == "</code>") --m_inCode;
				return;
			}
		}

		m_isTag = false;
		m_endIndex = 0;

		// else skip to the next valid tag
		while (m_endIndex < m_text.length) {
			auto idx = m_text[m_endIndex .. $].indexOf('<');
			if (idx < 0) {
				m_endIndex = m_text.length;
				return;
			}

			auto tlen = getTagLength(m_text[m_endIndex+idx .. $]);
			if (tlen > 0) {
				m_endIndex += idx;
				return;
			}

			m_endIndex += idx + 1;
		}
	}

	private static size_t getTagLength(string text)
	{
		assert(text.startsWith('<'));

		// skip HTML comment
		if (text.startsWith("<!--")) {
			auto idx = text[4 .. $].indexOf("-->");
			if (idx < 0) return 0;
			return idx+4+3;
		}

		auto idx = text.indexOf(">");

		// is this a (potentially) valid tag?
		if (idx < 2 || (!text[1].isAlpha && text[1] != '#' && text[1] != '/')) {
			// found no match, return escaped '<'
			logTrace("Found stray '<' in DDOC string.");
			return 0;
		}

		return idx + 1;
	}
}

unittest {
	import std.algorithm.comparison : equal;
	alias E = HTMLTagStream.Element;
	assert(HTMLTagStream("<foo").equal([E("<foo", false, false)]));
	assert(HTMLTagStream("<foo>bar").equal([E("<foo>", true, false), E("bar", false, false)]), HTMLTagStream("<foo>bar").array.to!string);
	assert(HTMLTagStream("foo<bar>").equal([E("foo", false, false), E("<bar>", true, false)]));
	assert(HTMLTagStream("<code>foo</code>").equal([E("<code>", true, true), E("foo", false, true), E("</code>", true, false)]), HTMLTagStream("<code>foo</code>").array.to!string);
	assert(HTMLTagStream("foo<code>").equal([E("foo", false, false), E("<code>", true, true)]), HTMLTagStream("foo<code>").array.to!string);
}

private void htmlEscape(R)(ref R dst, string str)
{
	foreach (size_t i, char ch; str) {
		switch (ch) {
			default: dst.put(ch); break;
			case '<': dst.put("&lt;"); break;
			case '>': dst.put("&gt;"); break;
			case '&':
				if (i+1 < str.length && (str[i+1].isAlpha || str[i+1] == '#')) dst.put('&');
				else dst.put("&amp;");
				break;
		}
	}
}

private string skipUrl(ref string ln)
{
	if( !ln.startsWith("http://") && !ln.startsWith("http://") )
		return null;

	bool saw_dot = false;
	size_t i = 7;

	for_loop:
	while( i < ln.length ){
		switch( ln[i] ){
			default:
				break for_loop;
			case 'a': .. case 'z':
			case 'A': .. case 'Z':
			case '0': .. case '9':
			case '_', '-', '?', '=', '%', '&', '/', '+', '#', '~':
				break;
			case '.':
				saw_dot = true;
				break;
		}
		i++;
	}

	if( saw_dot ){
		auto ret = ln[0 .. i];
		ln = ln[i .. $];
		return ret;
	} else return null;
}

private string skipIdent(ref string str)
{
	static import std.uni;

	string strcopy = str;

	if (str.length >= 2 && str[0] == '.' && (str[1].isAlpha || str[1] == '_'))
		str.popFront();

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
	foreach (string ln; lines) {
		// macro definitions are of the form IDENT = ...
		auto pidx = ln.indexOf('=');
		if (pidx > 0) {
			auto tmpnam = ln[0 .. pidx].strip();
			// got new macro definition?
			if (isIdent(tmpnam)) {

				// strip the previous macro
				if (name.length) macros[name] = macros[name].stripDD();

				// start parsing the new macro
				name = tmpnam;
				macros[name] = stripLeftDD(ln[pidx+1 .. $]);
				continue;
			}
		}

		// append to previous macro definition, if any
		macros[name] ~= "\n" ~ ln;
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

private string stripLeftDD(string s)
{
	while (!s.empty && (s.front == ' ' || s.front == '\t' || s.front == '\r' || s.front == '\n'))
		s.popFront();
	return s;
}

private string specialStrip(string s)
{
	import std.algorithm : among;

	// strip trailing whitespace for all lines but the last
	size_t idx = 0;
	while (true) {
		auto nidx = s[idx .. $].indexOf('\n');
		if (nidx < 0) break;
		nidx += idx;
		auto strippedfront = s[0 .. nidx].stripRightDD();
		s = strippedfront ~ "\n" ~ s[nidx+1 .. $];
		idx = strippedfront.length + 1;
	}

	// strip the first character, if whitespace
	if (!s.empty && s.front.among!(' ', '\t', '\n', '\r')) s.popFront();

	return s;
}

private string stripRightDD(string s)
{
	while (!s.empty && (s.back == ' ' || s.back == '\t' || s.back == '\r' || s.back == '\n'))
		s.popBack();
	return s;
}

private string stripDD(string s)
{
	return s.stripLeftDD.stripRightDD;
}


shared static this()
{
	s_standardMacros =
		[
		 `B`: `<b>$0</b>`,
		 `I`: `<i>$0</i>`,
		 `U`: `<u>$0</u>`,
		 `P` : `<p>$0</p>`,
		 `DL` : `<dl>$0</dl>`,
		 `DT` : `<dt>$0</dt>`,
		 `DD` : `<dd>$0</dd>`,
		 `TABLE` : `<table>$0</table>`,
		 `TR` : `<tr>$0</tr>`,
		 `TH` : `<th>$0</th>`,
		 `TD` : `<td>$0</td>`,
		 `OL` : `<ol>$0</ol>`,
		 `UL` : `<ul>$0</ul>`,
		 `LI` : `<li>$0</li>`,
		 `LINK` : `<a href="$0">$0</a>`,
		 `LINK2` : `<a href="$1">$+</a>`,
		 `LPAREN` : `(`,
		 `RPAREN` : `)`,

		 `RED` :   `<font color=red>$0</font>`,
		 `BLUE` :  `<font color=blue>$0</font>`,
		 `GREEN` : `<font color=green>$0</font>`,
		 `YELLOW` : `<font color=yellow>$0</font>`,
		 `BLACK` : `<font color=black>$0</font>`,
		 `WHITE` : `<font color=white>$0</font>`,

		 `D_CODE` : `<pre class="d_code">$0</pre>`,
		 `D_COMMENT` : `$(GREEN $0)`,
		 `D_STRING`  : `$(RED $0)`,
		 `D_KEYWORD` : `$(BLUE $0)`,
		 `D_PSYMBOL` : `$(U $0)`,
		 `D_PARAM` : `$(I $0)`,
		 `BACKTICK`: "`",
		 `DDOC_BACKQUOTED`: `$(D_INLINECODE $0)`,
		 //`D_INLINECODE`: `<pre style="display:inline;" class="d_inline_code">$0</pre>`,
		 `D_INLINECODE`: `<code class="lang-d">$0</code>`,

		 `DDOC` : `<html>
  <head>
    <META http-equiv="content-type" content="text/html; charset=utf-8">
    <title>$(TITLE)</title>
  </head>
  <body>
  <h1>$(TITLE)</h1>
  $(BODY)
  </body>
</html>`,

		 `DDOC_COMMENT` : `<!-- $0 -->`,
		 `DDOC_DECL` : `$(DT $(BIG $0))`,
		 `DDOC_DECL_DD` : `$(DD $0)`,
		 `DDOC_DITTO` : `$(BR)$0`,
		 `DDOC_SECTIONS` : `$0`,
		 `DDOC_SUMMARY` : `$0$(BR)$(BR)`,
		 `DDOC_DESCRIPTION` : `$0$(BR)$(BR)`,
		 `DDOC_AUTHORS` : "$(B Authors:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_BUGS` : "$(RED BUGS:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_COPYRIGHT` : "$(B Copyright:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_DATE` : "$(B Date:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_DEPRECATED` : "$(RED Deprecated:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_EXAMPLES` : "$(B Examples:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_HISTORY` : "$(B History:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_LICENSE` : "$(B License:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_RETURNS` : "$(B Returns:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_SEE_ALSO` : "$(B See Also:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_STANDARDS` : "$(B Standards:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_THROWS` : "$(B Throws:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_VERSION` : "$(B Version:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_SECTION_H` : `$(B $0)$(BR)$(BR)`,
		 `DDOC_SECTION` : `$0$(BR)$(BR)`,
		 `DDOC_MEMBERS` : `$(DL $0)`,
		 `DDOC_MODULE_MEMBERS` : `$(DDOC_MEMBERS $0)`,
		 `DDOC_CLASS_MEMBERS` : `$(DDOC_MEMBERS $0)`,
		 `DDOC_STRUCT_MEMBERS` : `$(DDOC_MEMBERS $0)`,
		 `DDOC_ENUM_MEMBERS` : `$(DDOC_MEMBERS $0)`,
		 `DDOC_TEMPLATE_MEMBERS` : `$(DDOC_MEMBERS $0)`,
		 `DDOC_PARAMS` : "$(B Params:)$(BR)\n$(TABLE $0)$(BR)",
		 `DDOC_PARAM_ROW` : `$(TR $0)`,
		 `DDOC_PARAM_ID` : `$(TD $0)`,
		 `DDOC_PARAM_DESC` : `$(TD $0)`,
		 `DDOC_BLANKLINE` : `$(BR)$(BR)`,

		 `DDOC_ANCHOR` : `<a name="$1"></a>`,
		 `DDOC_PSYMBOL` : `$(U $0)`,
		 `DDOC_KEYWORD` : `$(B $0)`,
		 `DDOC_PARAM` : `$(I $0)`,

		 `DDOX_UNITTEST_HEADER`: ``,
		 `DDOX_UNITTEST_FOOTER`: ``
		 ];
	import std.datetime : Clock;
	auto now = Clock.currTime();
	s_standardMacros["DATETIME"] = "%s %s %s %s:%s:%s %s".format(
		now.dayOfWeek.to!string.capitalize, now.month.to!string.capitalize,
		now.day, now.hour, now.minute, now.second, now.year);
	s_standardMacros["YEAR"] = now.year.to!string;
}


import std.stdio;
unittest {
	auto src = "$(M a b)\n$(M a\nb)\nMacros:\n	M =     -$0-\n";
	auto dst = "-a b-\n-a\nb-\n";
	assert(formatDdocComment(src) == dst);
}

unittest {
	auto src = "\n  $(M a b)\n$(M a  \nb)\nMacros:\n	M =     -$0-  \n\nN=$0";
	auto dst = "-a b-\n-a\nb-\n";
	assert(formatDdocComment(src) == dst);
}

unittest {
	auto src = "$(M a, b)\n$(M a,\n    b)\nMacros:\n	M = -$1-\n\n	+$2+\n\n	N=$0";
	auto dst = "-a-\n\n	+b+\n-a-\n\n	+    b+\n";
	assert(formatDdocComment(src) == dst);
}

unittest {
	auto src = "$(GLOSSARY a\nb)\nMacros:\n	GLOSSARY = $(LINK2 glossary.html#$0, $0)";
	auto dst = "<a href=\"glossary.html#a\nb\">a\nb</a>\n";
	assert(formatDdocComment(src) == dst);
}

unittest {
	auto src = "a > b < < c > <a <# </ <br> <abc> <.abc> <-abc> <+abc> <0abc> <abc-> <> <!-- c --> <!--> <! > <!-- > >a.";
	auto dst = "a &gt; b &lt; &lt; c &gt; <a <# </ <br> <abc> &lt;.abc&gt; &lt;-abc&gt; &lt;+abc&gt; &lt;0abc&gt; <abc-> &lt;&gt; <!-- c --> &lt;!--&gt; &lt;! &gt; &lt;!-- &gt; &gt;a.\n";
	assert(formatDdocComment(src) == dst);
}

unittest {
	auto src = "& &a &lt; &#lt; &- &03; &;";
	auto dst = "&amp; &a &lt; &#lt; &amp;- &amp;03; &amp;;\n";
	assert(formatDdocComment(src) == dst);
}

unittest {
	auto src = "<a href=\"abc\">test $(LT)peter@parker.com$(GT)</a>\nMacros:\nLT = &lt;\nGT = &gt;";
	auto dst = "<a href=\"abc\">test &lt;peter@parker.com&gt;</a>\n";
//writeln(formatDdocComment(src).splitLines().map!(s => "|"~s~"|").join("\n"));
	assert(formatDdocComment(src) == dst);
}

unittest {
	auto src = "$(LIX a, b, c, d)\nMacros:\nLI = [$0]\nLIX = $(LI $1)$(LIX $+)";
	auto dst = "[a][b][c][d]\n";
	assert(formatDdocComment(src) == dst);
}

unittest {
	auto src = "Testing `inline <code>`.";
	auto dst = "Testing <code class=\"lang-d\"><span class=\"pln\">inline </span><span class=\"pun\">&lt;</span><span class=\"pln\">code</span><span class=\"pun\">&gt;</span></code>.\n";
	assert(formatDdocComment(src) == dst);
}

unittest {
	auto src = "Testing `inline $(CODE)`.";
	auto dst = "Testing <code class=\"lang-d\">inline $(CODE)</code>.\n";
	assert(formatDdocComment(src));
}

unittest {
	auto src = "---\nthis is a `string`.\n---";
	auto dst = "<section><pre class=\"code\"><code class=\"lang-d\"><span class=\"kwd\">this is </span><span class=\"pln\">a </span><span class=\"str\">`string`<wbr/></span><span class=\"pun\">.</span></code></pre>\n</section>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // test for properly removed indentation in code blocks
	auto src = "  ---\n  testing\n  ---";
	auto dst = "<section><pre class=\"code\"><code class=\"lang-d\"><span class=\"pln\">testing</span></code></pre>\n</section>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // issue #99 - parse macros in parameter sections
	import std.algorithm : find;
	auto src = "Params:\n\tfoo = $(B bar)";
	auto dst = "<td> <b>bar</b></td></tr>\n</table>\n</section>\n";
	assert(formatDdocComment(src).find("<td> ") == dst);
}

unittest { // issue #89 (minimal test) - empty first parameter
	auto src = "$(DIV , foo)\nMacros:\nDIV=<div $1>$+</div>";
	auto dst = "<div >foo</div>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // issue #89 (complex test)
	auto src =
`$(LIST
$(DIV oops,
foo
),
$(DIV ,
bar
))
Macros:
LIST=$(UL $(LIX $1, $+))
LIX=$(LI $1)$(LIX $+)
UL=$(T ul, $0)
LI = $(T li, $0)
DIV=<div $1>$+</div>
T=<$1>$+</$1>
`;
	auto dst = "<ul><li><div oops>foo\n</div></li><li><div >bar\n</div></li></ul>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // issue #95 - trailing newlines must be stripped in macro definitions
	auto src = "$(FOO)\nMacros:\nFOO=foo\n\nBAR=bar";
	auto dst = "foo\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // missing macro closing clamp (because it's in a different section)
	auto src = "$(B\n\n)";
	auto dst = "(B\n<section><p>)\n</p>\n</section>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // closing clamp should be found in a different *paragraph* of the same section, though
	auto src = "foo\n\n$(B\n\n)";
	auto dst = "foo\n<section><p><b></b>\n</p>\n</section>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // more whitespace testing
	auto src = "$(M    a   ,   b   ,   c   )\nMacros:\nM =    A$0B$1C$2D$+E";
    auto dst = "A   a   ,   b   ,   c   B   a   C  b   D  b   ,   c   E\n";
    assert(formatDdocComment(src) == dst);
}

unittest { // more whitespace testing
	auto src = "  $(M  \n  a  \n  ,  \n  b \n  ,  \n  c  \n  )  \nMacros:\nM =    A$0B$1C$2D$+E";
    auto dst = "A  a\n  ,\n  b\n  ,\n  c\n  B  a\n  C  b\n  D  b\n  ,\n  c\n  E\n";
    assert(formatDdocComment(src) == dst);
}

unittest { // escape in backtick code
	auto src = "`<b>&amp;`";
	auto dst = "<code class=\"lang-d\"><span class=\"pun\">&lt;</span><span class=\"pln\">b</span><span class=\"pun\">&gt;&amp;</span><span class=\"pln\">amp</span><span class=\"pun\">;</span></code>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // escape in code blocks
	auto src = "---\n<b>&amp;\n---";
	auto dst = "<section><pre class=\"code\"><code class=\"lang-d\"><span class=\"pun\">&lt;</span><span class=\"pln\">b</span><span class=\"pun\">&gt;&amp;</span><span class=\"pln\">amp</span><span class=\"pun\">;</span></code></pre>\n</section>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // #81 empty first macro arguments
	auto src = "$(BOOKTABLE,\ntest)\nMacros:\nBOOKTABLE=<table $1>$+</table>";
	auto dst = "<table >test</table>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // #117 underscore identifiers as macro param
	auto src = "$(M __foo) __foo `__foo` $(D_CODE __foo)\nMacros:\nM=http://$1.com";
	auto dst = "http://_foo.com _foo <code class=\"lang-d\"><span class=\"pln\">__foo</span></code> <pre class=\"d_code\">_foo</pre>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // #109 dot followed by unicode character causes infinite loop
	auto src = ".”";
	auto dst = ".”\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // #119 dot followed by space causes assertion
	static class Ctx : BareContext {
		override LinkInfo lookupScopeSymbolLink(string name) {
			assert(name.length > 0 && name != ".");
			return LinkInfo.init;
		}
	}
	auto src = "---\n. writeln();\n---";
	auto dst = "<section><pre class=\"code\"><code class=\"lang-d\"><wbr/><span class=\"pun\">. </span><span class=\"pln\">writeln</span><span class=\"pun\">();</span></code></pre>\n</section>\n";
	assert(formatDdocComment(src, new Ctx) == dst);
}

unittest { // dot followed by non-identifier
	static class Ctx : BareContext {
		override LinkInfo lookupScopeSymbolLink(string name) {
			assert(name.length > 0 && name != ".");
			return LinkInfo.init;
		}
	}
	auto src = "---\n.()\n---";
	auto dst = "<section><pre class=\"code\"><code class=\"lang-d\"><wbr/><span class=\"pun\">.()</span></code></pre>\n</section>\n";
	assert(formatDdocComment(src, new Ctx) == dst);
}


unittest { // X-REF
	static class Ctx : BareContext {
		override LinkInfo lookupScopeSymbolLink(string name) {
			if (name == "foo") return LinkInfo("foo.html", null);
			else return LinkInfo.init;
		}
	}
	auto src = "`foo` `bar` $(D foo) $(D bar)\n\n---\nfoo bar\n---";
	auto dst = "<code class=\"lang-d\"><a href=\"foo.html\"><span class=\"pln\">foo</span></a></code> "
		~ "<code class=\"lang-d\"><span class=\"pln\">bar</span></code> "
		~ "<code class=\"lang-d\"><a href=\"foo.html\"><span class=\"pln\">foo</span></a></code> "
		~ "<code class=\"lang-d\"><span class=\"pln\">bar</span></code>\n"
		~ "<section><pre class=\"code\"><code class=\"lang-d\"><a href=\"foo.html\"><span class=\"pln\">foo</span></a>"
		~ "<span class=\"pln\"> bar</span></code></pre>\n</section>\n";
	assert(formatDdocComment(src, new Ctx) == dst);
}

unittest { // nested macro in $(D ...)
	auto src = "$(D $(NOP foo))\n\nMacros: NOP: $0";
	auto dst = "<code class=\"lang-d\"><span class=\"pln\">foo</span></code>\n<section></section>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // nested $(D $(D case)) (do not escape HTML tags)
	auto src = "$(D $(D foo))";
	auto dst = "<code class=\"lang-d\"><code class=\"lang-d\"><span class=\"pln\"><span class=\"pln\">foo</span></span></code></code>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // DDOX_NAMED_REF special macro
	static class Ctx : BareContext {
		override LinkInfo lookupScopeSymbolLink(string symbol) {
			if (symbol == "bar.baz")
				return LinkInfo("bar/baz.html", null);
			else
				return LinkInfo.init;
		}
	}

	auto src = "$(DDOX_NAMED_REF bar.baz, $(D foo))";
	auto dst = "<code class=\"lang-d\"><span class=\"pln\">foo</span></code>\n";
	auto dst_ctx = "<a href=\"bar/baz.html\" title=\"bar.baz\"><code class=\"lang-d\"><span class=\"pln\">foo</span></code></a>\n";
	assert(formatDdocComment(src) == dst);
	assert(formatDdocComment(src, new Ctx) == dst_ctx);
}

unittest { // DDOX_NAMED_REF special macro - handle invalid identifiers gracefully
	static class Ctx : BareContext {
		override LinkInfo lookupScopeSymbolLink(string symbol) {
			assert(symbol.length > 0);
			assert(!symbol.endsWith("."));
			return LinkInfo.init;
		}
	}

	auto src1 = "$(DDOX_NAMED_REF bar., $(D foo))";
	auto src2 = "$(DDOX_NAMED_REF , $(D foo))";
	auto dst = "<code class=\"lang-d\"><span class=\"pln\">foo</span></code>\n";
	assert(formatDdocComment(src1, new Ctx) == dst);
	assert(formatDdocComment(src2, new Ctx) == dst);
}

unittest { // #130 macro argument processing order
	auto src = "$(TEST)\nMacros:\nIGNORESECOND = [$1]\nDOLLARZERO = dzbegin $0 dzend\nTEST = before $(IGNORESECOND $(DOLLARZERO one, two)) after";
	auto dst = "before [dzbegin one, two dzend] after\n";
	assert(formatDdocComment(src) == dst);
}

unittest {
	assert(formatDdocComment("`<&`") == "<code class=\"lang-d\"><span class=\"pun\">&lt;&amp;</span></code>\n");
	assert(formatDdocComment("$(D <&)") == "<code class=\"lang-d\"><span class=\"pun\">&lt;&amp;</span></code>\n");
	assert(formatDdocComment("`foo") == "`foo\n");
	assert(formatDdocComment("$(D \"a < b\")") == "<code class=\"lang-d\"><span class=\"str\">\"a &lt; b\"</span></code>\n");
}

unittest {
	auto src = "$(REF x, foo,bar)\nMacros:\nREF=$(D $(REF_HELPER $1, $+))\nREF_HELPER=$2$(DOT_PREFIXED_SKIP $+).$1\nDOT_PREFIXED_SKIP=$(DOT_PREFIXED $+)\nDOT_PREFIXED=.$1$(DOT_PREFIXED $+))";
	auto dst = "<code class=\"lang-d\"><span class=\"pln\">foo<wbr/></span><span class=\"pun\">.</span><span class=\"pln\">bar</span><span class=\"pun\">)<wbr/>.</span><span class=\"pln\">x</span></code>\n";
	assert(formatDdocComment(src) == dst, formatDdocComment(src));
}

unittest {
	assert(formatDdocComment("$(A foo)\nMacros:A = $(B $+)\nB = bar$0") == "bar\n", formatDdocComment("$(A foo)\nMacros:A = $(B $+)\nB = bar$0"));
}

unittest { // #144 - extraneous <p>
	auto src = "$(UL\n\t$(LI Fixed: Item 1)\n\t$(LI Fixed: Item 2)\n)";
	auto dst = "<ul>\t<li>Fixed: Item 1</li>\n\t<li>Fixed: Item 2</li>\n</ul>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // #144 - extraneous <p>
	auto src = "foo\n\n$(UL\n\t$(LI Fixed: Item 1)\n\t$(LI Fixed: Item 2)\n)";
	auto dst = "foo\n<section><p><ul>\t<li>Fixed: Item 1</li>\n\t<li>Fixed: Item 2</li>\n</ul>\n</p>\n</section>\n";
	assert(formatDdocComment(src) == dst);
}

unittest { // #155 - single backtick
	auto src = "foo`bar\nbaz`bam";
	auto dst = "foo`bar\nbaz`bam\n";
	assert(formatDdocComment(src) == dst, formatDdocComment(src));
}
