///
module test;

///
@property auto foo(int a, int b)
{
	return a + b;
}

///
auto bar(T1, T2)(T1 a, T2 b)
{
	return a + b;
}

///
ref auto baz(T)(ref T a, ref T b, bool what)
{
	return what ? b : a;
}
