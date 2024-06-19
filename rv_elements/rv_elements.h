// 绕地rv转换为轨道根数
#include <vector>
#include <math.h>
double mu = 3.986005e5;
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
    return v1.at(0) * v2.at(0) + v1.at(1) * v2.at(1) + v1.at(2) * v2.at(2);
}
std::vector<double> operator+(std::vector<double> v1, std::vector<double> v2)
{
    std::vector<double> result;
    for (size_t i = 0; i < v1.size(); ++i)
        result.push_back(v1.at(i) + v2.at(i));
    return result;
}
std::vector<double> operator-(std::vector<double> v1)
{
    for (auto &i : v1)
        i = -i;
    return v1;
}
std::vector<double> operator-(std::vector<double> v1, std::vector<double> v2)
{
    return v1 + (-v2);
}
std::vector<double> operator*(double num, std::vector<double> v)
{
    return std::vector<double>{num * v.at(0), num * v.at(1), num * v.at(2)};
}

std::vector<double> rv2eles(std::vector<double> rv)
{
    std::vector<double> eles(6);
    std::vector<double> r(rv.begin(), rv.begin() + 3);
    double r_norm = norm(r);
    std::vector<double> v(rv.begin() + 3, rv.end());
    double v_norm = norm(v);
    std::vector<double> h = cross(r, v);
    double h_norm = norm(h);
    std::vector<double> Omega = cross(std::vector<double>{0, 0, 1}, h);
    std::vector<double> B = cross(v, h) - (mu / r_norm) * r;
    // Apogee(km)
    eles.at(0) = -mu / 2 / (pow(v_norm, 2) / 2 - mu / r_norm);
    // Eccentricity
    eles.at(1) = sqrt(1 - pow(h_norm, 2) / mu / eles.at(0));
    // Inclination(rad)
    eles.at(2) = acos(dot(std::vector<double>{0, 0, 1}, h) / h_norm);
    // Right Ascension of Ascending Node(rad)
    eles.at(3) = Omega.at(1) >= 0 ? acos(dot(Omega, std::vector<double>{1, 0, 0}) / norm(Omega)) : 2 * acos(-1) - acos(dot(Omega, std::vector<double>{1, 0, 0}) / norm(Omega));
    // Argument of Perigee(rad)
    eles.at(4) = cross(Omega, B).at(2) >= 0 ? acos(dot(Omega, B) / norm(Omega) / norm(B)) : 2 * acos(-1) - acos(dot(Omega, B) / norm(Omega) / norm(B));
    // True Anomaly(rad)
    eles.at(5) = cross(B, r).at(2) >= 0 ? acos((pow(h_norm, 2) / mu / r_norm - 1) / 1) : 2 * acos(-1) - acos((pow(h_norm, 2) / mu / r_norm - 1) / 1);
    return eles;
}