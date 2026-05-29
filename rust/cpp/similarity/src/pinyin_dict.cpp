#include <stdint.h>
#include <unordered_map>

typedef uint8_t uchar;
typedef uint16_t ushort;

// 懒加载：避免在 DLL 加载时（DllMain / loader lock 下）初始化大型 map。
// 函数局部 static 在 C++11 中保证线程安全，且仅在首次调用时构造。
const std::unordered_map<ushort, std::pair<uchar, uchar>>& get_pinyin_dict() {
    static const std::unordered_map<ushort, std::pair<uchar, uchar>> dict = {
#include "pinyin_dict.txt"
    };
    return dict;
}
