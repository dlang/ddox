///
module test;

///
ref int foo(return ref int a) @safe
{
	return a;
}

///
int* foo(return /*scope*/ int* a) @safe
{
	return a;
}

///
ref int* foo(scope return ref int* a) @safe
{
	return a;
}

///
struct S
{
@safe:
	///
	ref S foo() return
	{
		return this;
	}

	///
	ref S foo() return scope
	{
		return this;
	}

	///
	S foo() return scope
	{
		return this;
	}

	int* p;
}
