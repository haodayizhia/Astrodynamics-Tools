// 绕地rv转换为轨道根数函数
#include <vector>
double mu = 3.986005e14;
double norm(double x, double y, double z)
{
    return sqrt(x * x + y * y + z * z);
}
std::vector<double> cross(std::vector<double> v1, std::vector<double> v2)
{
    return std::vector<double>{v1.at(1) * v2.at(2) - v1.at(2) * v2.at(1),
                               v1.at(2) * v2.at(0) - v1.at(0) * v2.at(2),
                               v1.at(0) * v2.at(1) - v1.at(1) * v2.at(0)};
}
std::vector<double> rv2eles(std::vector<double> rv)
{
    std::vector<double> eles(6);
    double r_norm = norm(rv.at(0), rv.at(1), rv.at(2));
    double v_norm = norm(rv.at(3), rv.at(4), rv.at(5));
    // Apogee:km
    eles.at(0) = -mu / 2 * (pow(v_norm, 2) / 2 - mu / r_norm);
    eles.at(1) = 
}