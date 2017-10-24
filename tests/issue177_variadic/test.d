module test;

import core.stdc.stdarg;

class C
{}

///
void bug(int[4] args...)
{
}

///
void bug(int[] args...)
{
}

///
void bug(scope C c...)
{
}

///
void bug(...)
{
}

///
extern(C) void bug(int cnt, ...)
{
}

///
alias FT1 = void function(int[4] args...);

///
alias FT2 = void function(int[] args...);

///
alias FT3 = void function(scope C c...);

///
alias FT4 = void function(...);

///
extern(C) alias FT5 = void function(int cnt, ...);

///
void function(int[4] args...) var1;

///
void function(int[] args...) var2;

///
void function(scope C c...) var3;

///
void function(...) var4;

///
extern(C) void function(int cnt, ...) var5;
