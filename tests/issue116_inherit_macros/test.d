/**
Macros:
MODULE_MACRO=module macro
*/
module test;

/// $(MODULE_MACRO)
void f() {}

/**
Macros:
STRUCT_MACRO=struct macro
*/
struct S
{
    /// $(MODULE_MACRO) $(STRUCT_MACRO)
    void g() {}
}
