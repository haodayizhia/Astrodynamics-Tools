#include <iostream>
#include <vector>
#include <string>
#include <sstream>

class my_matrix
{
	friend my_matrix mcross(const my_matrix &m1, const my_matrix &m2);

public:
	my_matrix() = default;
	my_matrix(std::istream &in);
	void print() const;
	std::vector<std::vector<double>>::size_type rol() const { return data.size(); }; // 计算行数
	std::vector<double>::size_type col() const
	{
		if (data.empty())
			return 0;
		else
			return data[0].size();
	}; // 计算列数
	// 矩阵叉乘
	my_matrix cross(const my_matrix &m) const;
	// 求模
	double mol() const;
	double mol2() const;

private:
	std::vector<std::vector<double>> data;
};