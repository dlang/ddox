module test;

/// Returns:
///     true if T is a symbol or literal
/// Params:
///     T = Type or symbol
template isSymbol(T)
{
    enum isSymbol = !is(T);
}
/// ditto
template isSymbol(alias T)
{
    enum isSymbol = !is(T);
}