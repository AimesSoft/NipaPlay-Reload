#include "example_calculator.h"

#include <algorithm>
#include <cctype>

namespace nipaplay::native {

int32_t ExampleCalculator::add(int32_t a, int32_t b) const {
    return a + b;
}

std::string ExampleCalculator::processText(std::string_view input) const {
    std::string result;
    result.reserve(input.size() + 8);
    result.append("[NpNative] ");
    for (char c : input) {
        result.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(c))));
    }
    return result;
}

} // namespace nipaplay::native
