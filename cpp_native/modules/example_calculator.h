#pragma once
#include <cstdint>
#include <string>
#include <string_view>

namespace nipaplay::native {

/// 示例模块 — 用于验证 C++ → Dart FFI 链路
class ExampleCalculator {
public:
    ExampleCalculator() = default;
    ~ExampleCalculator() = default;

    // 禁止拷贝，允许移动
    ExampleCalculator(const ExampleCalculator&) = delete;
    ExampleCalculator& operator=(const ExampleCalculator&) = delete;
    ExampleCalculator(ExampleCalculator&&) = default;
    ExampleCalculator& operator=(ExampleCalculator&&) = default;

    /// 简单加法
    [[nodiscard]] constexpr int32_t add(int32_t a, int32_t b) const {
        return a + b;
    }

    /// 处理文本：将输入转为大写并添加前缀
    [[nodiscard]] std::string processText(std::string_view input) const;
};

} // namespace nipaplay::native
