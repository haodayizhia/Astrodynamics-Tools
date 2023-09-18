// 计算三维空间坐标系旋转,逆时针画v1到v2的弧
#include <iostream>
#include <vector>
#include <cmath>

#define pi 3.141592653

// (r,theta,phi)转换到(x,y,z)
std::vector<double> convert1(const std::vector<double> &v)
{
    return {v[0] * sin(v[1] / 180 * pi) * cos(v[2] / 180 * pi), v[0] * sin(v[1] / 180 * pi) * sin(v[2] / 180 * pi), v[0] * cos(v[1] / 180 * pi)};
}
// 弧段换算到[0,2pi]
double convert2(double a)
{
    return a >= 0 ? fmod(a, 2 * pi) : 2 * pi + fmod(a, 2 * pi);
}
// 向量叉乘
std::vector<double> cross(const std::vector<double> &v1, const std::vector<double> &v2)
{
    return {v1[1] * v2[2] - v1[2] * v2[1], v1[2] * v2[0] - v1[0] * v2[2], v1[0] * v2[1] - v1[1] * v2[0]};
}
// 向量点乘
double dot(const std::vector<double> &v1, const std::vector<double> &v2)
{
    return v1[0] * v2[0] + v1[1] * v2[1] + v1[2] * v2[2];
}
// 模
double mol(const std::vector<double> &v)
{
    return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}
int main(int argc, char *argv[])
{
    // 新坐标系的xy平面的两个向量v1,v2
    std::vector<double> v1 = convert1({1, 15, 60});
    std::vector<double> v2 = convert1({1, 60, 60});
    // 法向量z
    std::vector<double> z = cross(v1, v2);
    // 向量v1到v2的夹角
    double delta = z[2] >= 0 ? acos(dot(v1, v2) / mol(v1) / mol(v2)) : 2 * pi - acos(dot(v1, v2) / mol(v1) / mol(v2));
    if (z[2] < 0)
        z = {-z[0], -z[1], -z[2]};
    // 倾角i
    double i = acos(dot(z, {0, 0, 1}) / mol(z));
    // 升交点方向
    std::vector<double> vomega = cross({0, 0, 1}, z);
    // 升交点经度
    double omega = vomega[1] > 0 ? acos(dot(vomega, {1, 0, 0}) / mol(vomega)) : 2 * pi - acos(dot(vomega, {1, 0, 0}) / mol(vomega));
    // 需要绕z轴逆时针旋转的角度a1
    double a1 = omega - pi / 2;
    // 绕y轴逆时针旋转i后，需要绕z轴逆时针旋转的角度a2
    double a2 = pi / 2 + (cross(vomega, v1)[2] >= 0 ? acos(dot(vomega, v1) / mol(vomega) / mol(v1)) : 2 * pi - acos(dot(vomega, v1) / mol(vomega) / mol(v1)));
    std::cout << a1 / pi * 180 << ' ' << i / pi * 180 << ' ' << a2 / pi * 180 << ' ' << delta / pi * 180 << std::endl;
    return 0;
}