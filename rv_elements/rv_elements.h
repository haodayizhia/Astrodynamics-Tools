// 绕地rv转换为轨道根数
#include <vector>
#include <math.h>
double mu = 3.986005e14;
double norm(std::vector<double> vec)
{
    return sqrt(pow(vec.at(0), 2) + pow(vec.at(1), 2) + pow(vec.at(2), 2));
}
std::vector<double> cross(std::vector<double> v1, std::vector<double> v2)
{
    return std::vector<double>{v1.at(1) * v2.at(2) - v1.at(2) * v2.at(1),
                               v1.at(2) * v2.at(0) - v1.at(0) * v2.at(2),
                               v1.at(0) * v2.at(1) - v1.at(1) * v2.at(0)};
}
double dot(std::vector<double> v1, std::vector<double> v2)
{
    return v1.at(1) * v2.at(1) + v1.at(2) * v2.at(2) + v1.at(3) * v2.at(3);
}
std::vector<double> rv2eles(std::vector<double> rv)
{
    std::vector<double> eles(6);
    std::vector<double> r(rv.begin(), rv.begin() + 2);
    double r_norm = norm(r);
    std::vector<double> v(rv.begin() + 3, rv.end());
    double v_norm = norm(v);
    std::vector<double> h = cross(r, v);
    double h_norm = norm(h);
    std::vector<double> Omega = cross(std::vector<double>{0, 0, 1}, h);
    // Apogee(km)
    eles.at(0) = -mu / 2 * (pow(v_norm, 2) / 2 - mu / r_norm);
    // Eccentricity
    eles.at(1) = sqrt(1 - pow(h_norm, 2) / mu / eles.at(0));
    // Inclination(rad)
    eles.at(2) = acos(dot(std::vector<double>{0, 0, 1}, h) / h_norm);
    // Right Ascension of Ascending Node(rad)
    eles.at(3) = acos
}