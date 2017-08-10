module test;

/// IBase
interface IBase(T)
{
	void func();
}
/// IDerived
interface IDerived : IBase!int
{
	void func2();
}
/// CBase
class CBase(T)
{
	void func();
}
/// CDerived
class CDerived : CBase!int
{
	void func2();
}
