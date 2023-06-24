#include "my_matrix.h"

#include <string>
#include <sstream>

my_matrix::my_matrix(std::istream &in)
{
	double num;
	std::string s;
	std::cout << "input matrix by line, end by empty: " << std::endl;
	while (getline(in, s) && !s.empty())
	{
		std::vector<double> vb;
		std::stringstream ss(s);
		while (ss >> num)
			vb.push_back(num);
		if (data.size() != 0 && vb.size() != data[0].size())
		{
			std::cerr << "input error, again this line!" << std::endl;
			continue;
		}
		data.push_back(vb);
	}
}
void my_matrix::print() const
{
	for (auto &i : data)
	{
		for (auto &j : i)
			std::cout << j << ' ';
		std::cout << std::endl;
	}
}
