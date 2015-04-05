module test;

struct Test(T) {
	static struct arr { enum dimensions = 2; }
	int opApply(int delegate(immutable ptrdiff_t[arr.dimensions], ref T) @safe nothrow @nogc dg) @safe nothrow @nogc { return 0; }
	int opApply(int delegate(immutable ptrdiff_t[arr.dimensions], ref const(T)) @safe nothrow @nogc dg) const @safe nothrow @nogc { return 0; }
}
