#include <iostream>
#include <string>
#include <fstream>
#include <sstream>
#include "rv_elements.h"
int main(int argc, char *argv[])
{
    std::ifstream file("MEME_799500932_STARLINK-31920_1520146_Operational_1401414420_UNCLASSIFIED.txt");
    std::ofstream ofile("1.txt");
    std::string line;
    for (int i = 0; i < 4; ++i)
    {
        std::getline(file, line);
    }
    std::vector<std::vector<double>> date_rv;
    // std::vector<std::vector<double>> date_eles;
    int lineNumber = 0;
    int lineOffset = 4;
    while (std::getline(file, line))
    {
        if (lineNumber % lineOffset == 0)
        {
            std::istringstream iss(line);
            double value;
            std::vector<double> row;
            while (iss >> value)
                row.push_back(value);
            date_rv.push_back(row);
        }
        ++lineNumber;
    }
    for (auto iterator = date_rv.cbegin(); iterator != date_rv.cend(); ++iterator)
    {
        // std::vector<double> row = {(*iterator).front()};
        std::vector<double> eles = rv2eles(std::vector<double>((*iterator).begin() + 1, (*iterator).end()));
        fprintf(ofile, "%.3f", (*iterator).front());
        for (auto i : eles)
            ofile << ' ' << i;
        ofile << std::endl;
        // row.insert(row.end(), eles.begin(), eles.end());
        // date_eles.push_back(row);
    }
}