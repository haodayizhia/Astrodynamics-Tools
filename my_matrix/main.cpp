#include <iostream>
#include <fstream>
#include <time.h>
#include "my_matrix.cpp"
int main(int argc, char *argv[])
{
	clock_t start, end;
	start = clock();
	std::ofstream out("a.txt");
	int num = 100;
	for (int i = 0; i < num; ++i)
	{
		for (int j = 0; j < num; ++j)
			out << (double(rand()%300))/500 << ' ';
		out << std::endl;
	}
	out.close();
	std::ifstream in("a.txt");
	my_matrix mmtrix(in);
	std::cout << mmtrix.mol() << std::endl;
	end = clock();
	std::cout << "it takes " << (end - start) / CLOCKS_PER_SEC << " s" << std::endl;
	return 0;
}