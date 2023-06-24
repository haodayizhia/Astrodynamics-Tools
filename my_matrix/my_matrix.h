#include <iostream>
#include <vector>
#include <string>
#include <sstream>

class my_matrix
{
public:
	my_matrix(std::istream &in);
	void print() const;

private:
	std::vector<std::vector<double>> data;
};