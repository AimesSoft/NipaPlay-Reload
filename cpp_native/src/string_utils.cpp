#include "nipaplay_native/types.h"

#include <cstdlib>
#include <cstring>
#include <string>

/// 分配 NpString（内部使用 malloc）
/// 返回的 NpString.data 由 malloc 分配，需由 np_string_free 释放
/// 注意：此函数为 C++ 内部辅助函数，不使用 extern "C"，
/// 因为参数含 C++ 引用类型，违反 C 链接规范
NpString np_string_alloc(const std::string& s) {
    // +1 for null terminator
    char* buf = static_cast<char*>(std::malloc(s.size() + 1));
    if (!buf) {
        return {nullptr, 0};
    }
    std::memcpy(buf, s.data(), s.size());
    buf[s.size()] = '\0';
    return {buf, static_cast<int32_t>(s.size())};
}
