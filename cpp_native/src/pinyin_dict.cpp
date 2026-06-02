#include "similarity_engine.h"

namespace nipaplay::native {

// 懒加载：避免在 DLL 加载时（DllMain / loader lock 下）初始化大型 map。
// 函数局部 static 在 C++11 中保证线程安全，且仅在首次调用时构造。
const std::unordered_map<sim_ushort, std::pair<sim_uchar, sim_uchar>>& get_pinyin_dict() {
    // pinyin_dict.txt 中的整数字面量窄化为 sim_uchar 是安全的（值域 0-255），
    // 但编译器会产生窄化转换警告，此处定向抑制。
#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable: 4244)
#elif defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wnarrowing"
#endif
    static const std::unordered_map<sim_ushort, std::pair<sim_uchar, sim_uchar>> dict = {
#include "pinyin_dict.txt"
    };
#ifdef _MSC_VER
#pragma warning(pop)
#elif defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic pop
#endif
    return dict;
}

} // namespace nipaplay::native
