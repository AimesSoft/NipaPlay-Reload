#include "danmaku_parser.h"

#include <pugixml.hpp>

#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable: 4996 5054)  // rapidjson: STL4015 std::iterator, C5054 enum |
#endif
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"  // rapidjson: std::iterator base class
#elif defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wtemplate-body"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"  // rapidjson: std::iterator base class
#pragma GCC diagnostic ignored "-Wclass-memaccess"          // rapidjson: memcpy on non-trivial type
#endif
#include <rapidjson/document.h>
#include <rapidjson/writer.h>
#include <rapidjson/stringbuffer.h>
#if defined(__clang__)
#pragma clang diagnostic pop
#elif defined(__GNUC__)
#pragma GCC diagnostic pop
#endif
#ifdef _MSC_VER
#pragma warning(pop)
#endif
#include <cstdlib>        // std::strtod, std::strtol, std::strtoll
#include <cstring>
#include <cstdio>
#include <array>
#include <algorithm>

namespace nipaplay {

// ──── XML entity decode table (C++20 data-driven approach) ────
// 使用 char 数组定义实体，避免源码中出现 HTML 实体字符串字面量
// （如 "&" 可能被某些工具误解析）

struct XmlEntity {
    const char chars[7]; // max entity length 6 + null pad
    const std::uint8_t len;
    const char decoded;
};

static constexpr XmlEntity kXmlEntities[] = {
    {{'&','a','m','p',';','\0','\0'}, 5, '&'},
    {{'&','l','t',';','\0','\0','\0'}, 4, '<'},
    {{'&','g','t',';','\0','\0','\0'}, 4, '>'},
    {{'&','q','u','o','t',';','\0'}, 6, '"'},
    {{'&','a','p','o','s',';','\0'}, 6, '\''},
};

// ──── 辅助函数 ────

std::string DanmakuParser::decodeXmlText(std::string_view input) {
    std::string result;
    result.reserve(input.size());
    for (size_t i = 0; i < input.size(); ) {
        if (input[i] == '&') [[unlikely]] {
            const auto rest = input.substr(i);
            bool matched = false;
            for (const auto& ent : kXmlEntities) {
                if (rest.size() >= ent.len &&
                    std::memcmp(rest.data(), ent.chars, ent.len) == 0) {
                    result += ent.decoded;
                    i += ent.len;
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                result += input[i];
                ++i;
            }
        } else [[likely]] {
            result += input[i];
            ++i;
        }
    }
    return result;
}

std::string DanmakuParser::colorToRgb(int32_t color_code) {
    const int32_t r = (color_code >> 16) & 0xFF;
    const int32_t g = (color_code >> 8) & 0xFF;
    const int32_t b = color_code & 0xFF;
    char buf[32];
    std::snprintf(buf, sizeof(buf), "rgb(%d,%d,%d)", r, g, b);
    return buf;
}

// ──── 数值解析辅助：从 string_view 解析数值 ────
// 使用 strtod/strtol/strtoll 替代 std::from_chars，
// 以兼容 macOS 部署目标低于 from_chars 可用版本的情况。

// 解析 double，失败返回 default_val
static double from_chars_double(std::string_view sv, double default_val) {
    if (sv.empty()) return default_val;
    const std::string tmp(sv);
    char* end = nullptr;
    const double val = std::strtod(tmp.c_str(), &end);
    return (end != tmp.c_str()) ? val : default_val;
}

// 解析 int32_t，失败返回 default_val
static int32_t from_chars_int32(std::string_view sv, int32_t default_val) {
    if (sv.empty()) return default_val;
    const std::string tmp(sv);
    char* end = nullptr;
    const long val = std::strtol(tmp.c_str(), &end, 10);
    return (end != tmp.c_str() && val >= INT32_MIN && val <= INT32_MAX) ? static_cast<int32_t>(val) : default_val;
}

// 解析 int64_t，失败返回 default_val
static int64_t from_chars_int64(std::string_view sv, int64_t default_val) {
    if (sv.empty()) return default_val;
    const std::string tmp(sv);
    char* end = nullptr;
    const long long val = std::strtoll(tmp.c_str(), &end, 10);
    return (end != tmp.c_str()) ? static_cast<int64_t>(val) : default_val;
}

bool DanmakuParser::parsePAttribute(std::string_view p_attr, DanmakuItem& item) {
    // p 属性格式: time,mode,fontsize,color,sendtime,pool,sender_hash,id[,weight]
    if (p_attr.empty()) return false;

    // 手动分割逗号分隔字段，避免 stringstream 分配开销
    // 使用 strtod/strtol/strtoll 从 string_view 解析数值。
    int32_t field_index = 0;
    size_t start = 0;
    size_t end = 0;

    while (end <= p_attr.size()) {
        if (end == p_attr.size() || p_attr[end] == ',') {
            std::string_view field(p_attr.data() + start, end - start);
            switch (field_index) {
                case 0: // time
                    item.time_seconds = from_chars_double(field, 0.0);
                    break;
                case 1: // mode
                    item.mode = from_chars_int32(field, 1);
                    break;
                case 2: // fontsize
                    item.font_size = from_chars_int32(field, 25);
                    break;
                case 3: // color
                    item.color_code = from_chars_int32(field, 16777215);
                    break;
                case 4: // sendtime
                    item.send_timestamp = from_chars_int64(field, 0);
                    break;
                case 5: // pool
                    item.pool = from_chars_int32(field, 0);
                    break;
                case 6: // sender_hash
                    if (!field.empty()) {
                        item.sender_hash = std::string(field);
                    }
                    break;
                case 7: // id
                    if (!field.empty()) {
                        item.danmaku_id = std::string(field);
                    }
                    break;
                case 8: // weight (optional)
                    item.weight = from_chars_int32(field, 0);
                    break;
                default:
                    break;
            }
            field_index++;
            start = end + 1;
        }
        end++;
    }

    // 至少需要 4 个字段 (time,mode,fontsize,color)
    return field_index >= 4;
}

std::string_view DanmakuParser::stripControlChars(std::string_view input, std::string& buffer) {
    bool has_control = false;
    for (size_t i = 0; i < input.size(); i++) {
        const auto c = static_cast<unsigned char>(input[i]);
        if (c <= 0x08 || c == 0x0B || c == 0x0C ||
            (c >= 0x0E && c <= 0x1F) || c == 0x7F) [[unlikely]] {
            has_control = true;
            break;
        }
    }
    if (!has_control) [[likely]] return input;

    buffer.clear();
    buffer.reserve(input.size());
    for (size_t i = 0; i < input.size(); i++) {
        unsigned char c = static_cast<unsigned char>(input[i]);
        if (!(c <= 0x08 || c == 0x0B || c == 0x0C ||
              (c >= 0x0E && c <= 0x1F) || c == 0x7F)) {
            buffer += input[i];
        }
    }
    return buffer;
}

// ──── DOM 解析 ────

// 辅助：将 DanmakuItem 写入 rapidjson Writer（XML 解析路径输出格式）
// 输出字段: t, c, y, r, fontSize, originalType — 与 Dart 侧 _buildBilibiliDanmakuComment 完全一致
// 还有 timestamp, senderId, cid, source 等元数据字段
static void writeDanmakuItemXml(rapidjson::Writer<rapidjson::StringBuffer>& writer, const DanmakuItem& item) {
    writer.StartObject();
    writer.Key("t");
    writer.Double(item.time_seconds);
    writer.Key("c");
    writer.String(item.content.c_str());
    writer.Key("y");
    writer.String(DanmakuParser::modeToType(item.mode));
    writer.Key("r");
    std::string color = DanmakuParser::colorToRgb(item.color_code);
    writer.String(color.c_str());
    writer.Key("fontSize");
    writer.Int(item.font_size);
    writer.Key("originalType");
    writer.Int(item.mode);

    // 可选字段: timestamp, senderId, cid
    if (item.send_timestamp > 0) {
        writer.Key("timestamp");
        writer.Int64(item.send_timestamp);
    }
    if (!item.sender_hash.empty() && item.sender_hash != "0") {
        writer.Key("senderId");
        writer.String(item.sender_hash.c_str());
    }
    if (!item.danmaku_id.empty() && item.danmaku_id != "0") {
        writer.Key("cid");
        writer.String(item.danmaku_id.c_str());
    }
    writer.Key("source");
    writer.String("bilibili");

    writer.EndObject();
}

std::string DanmakuParser::parseXmlDom(std::string_view xml_content) {
    pugi::xml_document doc;
    pugi::xml_parse_result result = doc.load_buffer(
        xml_content.data(), xml_content.size(),
        pugi::parse_default | pugi::parse_trim_pcdata
    );

    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    int32_t count = 0;

    writer.StartObject();
    writer.Key("comments");
    writer.StartArray();

    if (result) {
        pugi::xml_node root = doc.child("i");
        for (pugi::xml_node d_node = root.child("d"); d_node;
             d_node = d_node.next_sibling("d")) {
            DanmakuItem item{};
            const char* p_attr = d_node.attribute("p").as_string();
            if (!parsePAttribute(p_attr, item)) continue;

            const char* text = d_node.child_value();
            if (text[0] == '\0') continue;
            item.content = decodeXmlText(text);
            if (item.content.empty()) continue;

            writeDanmakuItemXml(writer, item);
            count++;
        }
    }

    writer.EndArray();
    writer.Key("count");
    writer.Int(count);
    writer.EndObject();

    return std::string(buffer.GetString(), buffer.GetSize());
}

// ──── 快速扫描回退 ────

std::string DanmakuParser::parseXmlFallback(std::string_view xml) {
    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    int32_t count = 0;

    writer.StartObject();
    writer.Key("comments");
    writer.StartArray();

    size_t pos = 0;
    while (pos < xml.size()) {
        // 查找 <d
        size_t d_start = xml.find("<d", pos);
        if (d_start == std::string_view::npos) break;

        // 查找 > 以确定标签结束位置
        size_t tag_end_pos = xml.find('>', d_start + 2);
        if (tag_end_pos == std::string_view::npos) { pos = d_start + 2; continue; }

        // 在标签范围内查找 p=" 属性
        std::string_view tag_content(xml.data() + d_start, tag_end_pos - d_start + 1);
        size_t p_attr_pos = tag_content.find("p=\"");
        if (p_attr_pos == std::string_view::npos) { pos = d_start + 2; continue; }

        // 提取 p 属性值
        size_t p_val_start = d_start + p_attr_pos + 3;
        size_t p_val_end = xml.find('"', p_val_start);
        if (p_val_end == std::string_view::npos || p_val_end > tag_end_pos) {
            pos = d_start + 2; continue;
        }

        std::string_view p_attr(xml.data() + p_val_start, p_val_end - p_val_start);

        // 提取文本内容: >...</d>
        size_t text_start = tag_end_pos + 1;
        size_t close_start = xml.find("</d>", text_start);
        if (close_start == std::string_view::npos) { pos = d_start + 2; continue; }

        std::string_view text_content(xml.data() + text_start, close_start - text_start);

        DanmakuItem item{};
        if (parsePAttribute(p_attr, item)) {
            item.content = decodeXmlText(text_content);
            if (!item.content.empty()) {
                writeDanmakuItemXml(writer, item);
                count++;
            }
        }

        pos = close_start + 4;
    }

    writer.EndArray();
    writer.Key("count");
    writer.Int(count);
    writer.EndObject();

    return std::string(buffer.GetString(), buffer.GetSize());
}

// ──── 公共接口 ────

std::string DanmakuParser::parseXmlToJson(std::string_view xml_content) {
    // 1. 控制字符预处理
    std::string ctrl_buffer;
    std::string_view clean_xml = stripControlChars(xml_content, ctrl_buffer);

    // 2. 尝试 DOM 解析
    std::string result = parseXmlDom(clean_xml);

    // 3. 如果 DOM 解析结果为空但输入包含 <d，则回退到扫描器
    //    （对应 Dart 侧：comments.isEmpty && xmlContent.contains('<d') 则走正则回退）
    if (result.find("\"count\":0") != std::string::npos &&
        clean_xml.find("<d") != std::string_view::npos) {
        // 检查是否是 DOM 解析成功但确实没有 <d> 子节点（如 <i> 存在但无 <d>）
        // 还是 DOM 解析失败导致结果为空
        // 尝试 fallback 扫描器
        std::string fallback_result = parseXmlFallback(clean_xml);
        // 如果 fallback 找到了弹幕，使用 fallback 结果
        if (fallback_result.find("\"count\":0") == std::string::npos) {
            return fallback_result;
        }
    }

    return result;
}

// ──── JSON 标准化 ────

// 辅助：从 rapidjson Value 中安全获取字符串
static std::string getStringField(const rapidjson::Value& obj, const char* key, const char* default_val = "") {
    if (!obj.HasMember(key)) return default_val;
    const auto& v = obj[key];
    if (v.IsString()) return std::string(v.GetString(), v.GetStringLength());
    return default_val;
}

// 辅助：从 rapidjson Value 中安全获取数值字段（double）
static double getDoubleField(const rapidjson::Value& obj, const char* key, double default_val = 0.0) {
    if (!obj.HasMember(key)) return default_val;
    const auto& v = obj[key];
    if (v.IsNumber()) return v.GetDouble();
    if (v.IsString()) {
        char* endp = nullptr;
        return std::strtod(v.GetString(), &endp);
    }
    return default_val;
}

// 辅助：从 rapidjson Value 中安全获取数值字段（int）
[[maybe_unused]] static int getIntField(const rapidjson::Value& obj, const char* key, int default_val = 0) {
    if (!obj.HasMember(key)) return default_val;
    const auto& v = obj[key];
    if (v.IsInt()) return v.GetInt();
    if (v.IsInt64()) return static_cast<int>(v.GetInt64());
    if (v.IsDouble()) return static_cast<int>(v.GetDouble());
    if (v.IsString()) return std::atoi(v.GetString());
    return default_val;
}

// 辅助：标准化弹幕类型字段（处理数值 type 和字符串 type）
// 与 Dart 侧 parseDanmakuListInBackground 的 type 处理逻辑一致
static std::string standardizeType(const rapidjson::Value& obj) {
    // 优先检查 "y" 字段（XML 解析结果格式）
    if (obj.HasMember("y") && obj["y"].IsString()) {
        std::string type_val = obj["y"].GetString();
        // 标准化类型字符串
        if (type_val == "scroll" || type_val == "right") return "scroll";
        if (type_val == "top") return "top";
        if (type_val == "bottom") return "bottom";
        return "scroll";
    }
    // 检查 "type" 字段（弹弹 play API JSON 格式）
    if (obj.HasMember("type")) {
        const auto& v = obj["type"];
        if (v.IsNumber()) {
            // 数值 type: 0=scroll, 1=top, 2=bottom (布局引擎格式)
            int type_int = v.GetInt();
            switch (type_int) {
                case 1: return "top";
                case 2: return "bottom";
                case 0:
                default: return "scroll";
            }
        }
        if (v.IsString()) {
            std::string type_val = v.GetString();
            if (type_val == "scroll" || type_val == "right") return "scroll";
            if (type_val == "top") return "top";
            if (type_val == "bottom") return "bottom";
            return "scroll";
        }
    }
    return "scroll";
}

// 标准化的 8 个字段名（不透传到输出）— C++20 constexpr array + ranges
static constexpr std::array<std::string_view, 8> kStandardFields = {
    "t", "c", "y", "r", "time", "content", "type", "color"
};

static bool isStandardField(std::string_view key) noexcept {
    return std::ranges::find(kStandardFields, key) != kStandardFields.end();
}

// 辅助：将 rapidjson Value 写入 Writer（递归）
static void writeRapidJsonValue(rapidjson::Writer<rapidjson::StringBuffer>& writer, const rapidjson::Value& v) {
    switch (v.GetType()) {
        case rapidjson::kNullType:   writer.Null(); break;
        case rapidjson::kFalseType:  writer.Bool(false); break;
        case rapidjson::kTrueType:   writer.Bool(true); break;
        case rapidjson::kObjectType:
            writer.StartObject();
            for (auto it = v.MemberBegin(); it != v.MemberEnd(); ++it) {
                writer.Key(it->name.GetString(), it->name.GetStringLength());
                writeRapidJsonValue(writer, it->value);
            }
            writer.EndObject();
            break;
        case rapidjson::kArrayType:
            writer.StartArray();
            for (auto it = v.Begin(); it != v.End(); ++it) {
                writeRapidJsonValue(writer, *it);
            }
            writer.EndArray();
            break;
        case rapidjson::kStringType:
            writer.String(v.GetString(), v.GetStringLength());
            break;
        case rapidjson::kNumberType:
            if (v.IsInt64()) writer.Int64(v.GetInt64());
            else if (v.IsUint64()) writer.Uint64(v.GetUint64());
            else if (v.IsDouble()) writer.Double(v.GetDouble());
            else if (v.IsInt()) writer.Int(v.GetInt());
            else if (v.IsUint()) writer.Uint(v.GetUint());
            break;
    }
}

std::string DanmakuParser::parseJsonToStandardized(std::string_view json_content) {
    rapidjson::Document doc;
    doc.Parse(json_content.data(), json_content.size());

    if (doc.HasParseError() || !doc.IsArray()) [[unlikely]] {
        return "{\"comments\":[],\"count\":0}";
    }

    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    int32_t count = 0;

    writer.StartObject();
    writer.Key("comments");
    writer.StartArray();

    for (rapidjson::SizeType i = 0; i < doc.Size(); i++) {
        const auto& item = doc[i];
        if (!item.IsObject()) [[unlikely]] continue;

        // ── 双源字段映射 ──

        // time: t → time, 或 time → time
        double time_val = 0.0;
        if (item.HasMember("t")) {
            time_val = getDoubleField(item, "t", 0.0);
        } else if (item.HasMember("time")) {
            time_val = getDoubleField(item, "time", 0.0);
        }

        // content: c → content, 或 content → content
        std::string content_val;
        if (item.HasMember("c")) {
            content_val = getStringField(item, "c", "");
        } else if (item.HasMember("content")) {
            content_val = getStringField(item, "content", "");
        }

        // type: y → type, 或 type → type（需标准化）
        std::string type_val = standardizeType(item);

        // color: r → color, 或 color → color
        std::string color_val;
        if (item.HasMember("r")) {
            color_val = getStringField(item, "r", "rgb(255,255,255)");
        } else if (item.HasMember("color")) {
            color_val = getStringField(item, "color", "rgb(255,255,255)");
        }

        // 验证：有内容且时间有效
        if (content_val.empty() || time_val < 0.0) continue;

        writer.StartObject();
        writer.Key("time");
        writer.Double(time_val);
        writer.Key("content");
        writer.String(content_val.c_str());
        writer.Key("type");
        writer.String(type_val.c_str());
        writer.Key("color");
        writer.String(color_val.c_str());

        // 透传所有非标准额外字段（fontSize, originalType, size, weight 等）
        // 与 Dart 侧逻辑一致：保留原始 Map 中不属于标准 8 字段的所有条目
        for (auto it = item.MemberBegin(); it != item.MemberEnd(); ++it) {
            const std::string_view key(it->name.GetString(), it->name.GetStringLength());
            if (!isStandardField(key)) {
                writer.Key(key.data(), static_cast<rapidjson::SizeType>(key.size()));
                writeRapidJsonValue(writer, it->value);
            }
        }

        writer.EndObject();
        count++;
    }

    writer.EndArray();
    writer.Key("count");
    writer.Int(count);
    writer.EndObject();

    return std::string(buffer.GetString(), buffer.GetSize());
}

} // namespace nipaplay
