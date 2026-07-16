#pragma once
#include <string>
#include <string_view>
#include <cstdint>

namespace nipaplay {

// 单条弹幕的内部表示
struct DanmakuItem {
    double time_seconds;        // 出现时间
    int32_t mode;               // 弹幕模式 (1=scroll, 4=bottom, 5=top, 6=reverse, 7=special)
    int32_t font_size;          // 字体大小
    int32_t color_code;         // 十进制颜色值 (0xBBGGRR 或原始值)
    int64_t send_timestamp;     // 发送时间戳
    int32_t pool;               // 弹幕池
    std::string sender_hash;    // 发送者哈希
    std::string danmaku_id;     // 弹幕ID
    int32_t weight;             // 权重（可能不存在，默认0）
    std::string content;        // 弹幕文本内容
};

class DanmakuParser {
public:
    // 解析 Bilibili XML 弹幕，返回预序列化 JSON 字符串
    // 输出格式: {"count":N,"comments":[{"t":...,"c":...,"y":...,"r":...,"fontSize":...,"originalType":...},...]}
    // 输出格式包含标准字段及 timestamp, senderId, cid, source 等元数据
    // 与 Dart 侧 convertBilibiliXmlDanmakuToJson 输出完全一致
    static std::string parseXmlToJson(std::string_view xml_content);

    // 解析弹幕 JSON 数组，返回标准化 JSON 字符串
    // 输出格式: {"count":N,"comments":[{"time":...,"content":...,"type":...,"color":...,...},...]}
    // 与 Dart 侧 parseDanmakuListInBackground 输出完全一致
    // 支持双源字段映射: t/time, c/content, y/type, r/color
    // 保留所有非标准额外字段（如 fontSize, originalType 等）
    static std::string parseJsonToStandardized(std::string_view json_content);

    // 将 mode 代码转为类型字符串
    static constexpr const char* modeToType(int32_t mode) noexcept {
        switch (mode) {
            case 4:  return "bottom";
            case 5:  return "top";
            case 1:
            case 6:
            default: return "scroll";
        }
    }

    // 将十进制颜色值转为 rgb(r,g,b) 格式
    static std::string colorToRgb(int32_t color_code);

private:
    // XML 特殊字符解码 & < > " '
    static std::string decodeXmlText(std::string_view input);

    // 解析 <d> 元素的 p 属性，提取各字段
    static bool parsePAttribute(std::string_view p_attr, DanmakuItem& item);

    // 使用 pugixml DOM 解析 XML
    static std::string parseXmlDom(std::string_view xml_content);

    // 使用快速扫描作为 DOM 解析失败时的回退
    static std::string parseXmlFallback(std::string_view xml_content);

    // 控制字符预处理（参考 pakku.js）
    // 去除 0x00-0x08, 0x0B-0x0C, 0x0E-0x1F, 0x7F
    static std::string_view stripControlChars(std::string_view input, std::string& buffer);
};

} // namespace nipaplay
