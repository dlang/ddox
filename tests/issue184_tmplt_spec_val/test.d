///
module test;

/// templates with specialization and default values
alias Type(int val) = int;
/// ditto
alias Type(int val : 1) = float;
/// ditto
alias Type(int val : 2 = 2) = double;
/// ditto
alias Type(int val : 3) = byte;
