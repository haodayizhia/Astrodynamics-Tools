#include <iostream>
#include "rv_elements.h"
int main(int argc, char *argv[])
{
    std::vector<double> rv = {-1354.8096454855, -5026.4640625937, -4574.6663759097, 5.0975301390, -4.4636431540, 3.3985706125};
    std::vector<double> eles = rv2eles(rv);
    for (auto i : eles)
        std::cout << i << ' ';
}