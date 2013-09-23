module app;

import ddox.main;

int main(string[] args)
{
	version(unittest) return 0;
	else return ddoxMain(args);
}
