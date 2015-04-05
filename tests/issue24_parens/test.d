module test;

/**
 * Example:
 * ---
 * // Find an '$(RPAREN)' in a buffer of 1024 bytes using an additional sentinel.
 * size_t length = 1024;
 * char[] buffer = new char[](length+1);
 * buffer[length] = '(';
 * auto pos = buffer.ptr.find!('(');
 * if (pos < length) { // was an actual find before the sentinel }
 * ---
 */
 int a;
