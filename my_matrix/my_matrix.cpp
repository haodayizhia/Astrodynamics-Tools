#include "my_matrix.h"
#include <algorithm>
#include <memory>

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
my_matrix my_matrix::cross(const my_matrix &m) const
{
	my_matrix result;
	auto rol1 = rol();
	auto col1 = col();
	auto col2 = m.col();
	auto rol2 = m.rol();
	if (col1 != rol2)
	{
		std::cerr << "fault cross product" << std::endl;
		exit(EXIT_FAILURE);
	}
	for (size_t i = 0; i < rol1; ++i)
	{
		double value = 0;
		for (size_t k = 0; k < col1; ++k)
		{
			value += data[i][k] * m.data[k][0];
		}
		result.data.push_back({value});
		for (size_t j = 1; j < col2; ++j)
		{
			value = 0;
			for (size_t k = 0; k < col1; ++k)
			{
				value += data[i][k] * m.data[k][j];
			}
			result.data[i].push_back(value);
		}
	}
	return result;
}
double process(const std::vector<std::vector<double>> &data, std::vector<double> now = std::vector<double>(0))
{
	double res = 0;
	size_t past = 0;
	for (size_t i = 0; i < data.size(); ++i)
	{
		auto used = now;
		if (std::find(used.cbegin(), used.cend(), i) != used.cend())
		{
			++past;
			continue;
		}
		double value = 0;
		if ((i - past) % 2)
			value = -data[used.size()][i];
		else
			value = data[used.size()][i];
		used.push_back(i);
		if (used.size() < data.size())
			value *= process(data, used);
		res += value;
	}
	return res;
}
double my_matrix::mol2() const
{
	if (col() != rol())
		std::cerr << "fault mol" << std::endl;
	return process(data);
}
double my_matrix::mol() const
{
	double result = 1;
	if (col() != rol())
		std::cerr << "fault mol" << std::endl;
	std::vector<std::shared_ptr<std::vector<double>>> m(col());
	for (size_t i = 0; i < rol(); ++i)
	{
		m[i] = std::make_shared<std::vector<double>>(data[i]);
	}
	for (int i = 0; i < col(); ++i)
	{
		// 若(i,i)元素为0，与后面第i个元素不为0的行交换
		if ((*m[i])[i] == 0)
		{
			for (int j = i + 1; j < rol(); ++j)
				if ((*m[j])[i] != 0)
					std::swap(m[i], m[j]);
		}
		// 如果后面的也为0，则结果为0
		if ((*m[i])[i] == 0)
			return 0;
		// 将后面行的第i个元素化为0
		for (int j = i + 1; j < rol(); j++)
		{
			if ((*m[j])[i] != 0)
			{
				double ratio = (*m[j])[i] / (*m[i])[i];
				for (int k = i; k < col(); ++k)
					(*m[j])[k] -= ratio * (*m[i])[k];
			}
		}
	}
	for (int i = 0; i < rol(); ++i)
		result *= (*m[i])[i];
	std::ofstream out("res.txt");
	for (auto i : m)
	{
		for (auto j : *i)
			out << j << ' ';
		out << std::endl;
	}
	return result;
}