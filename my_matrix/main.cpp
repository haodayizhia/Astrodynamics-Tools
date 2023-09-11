#include <iostream>
#include "my_matrix.cpp"
int main(int argc, char *argv[])
{
	my_matrix mmtrix(std::cin);
	mmtrix.print();
	return 0;
}