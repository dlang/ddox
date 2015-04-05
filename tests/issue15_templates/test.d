module test;

/// doc 1
template isValue(T)
{
    enum isValue = !is(T);
}

/// doc 2
template isValue(alias T)
{
    enum isValue = !is(T);
}

/// doc 3
template isEqual(alias A, alias B)
{
    static if( isValue!A && isValue!B && __traits(compiles, A == B))
        enum isEqual = A == B;
    else static if(!(isValue!A || isValue!B))
        enum isEqual = isSameType!(A, B);
    else
        enum isEqual = false;
}
/// ditto
template isEqual(alias A, B)
{
    enum isEqual = false;
}
/// ditto
template isEqual(A, alias B)
{
    enum isEqual = false;
}
/// ditto
template isEqual(A, B)
{
    enum isEqual = isSameType!(A, B);
}