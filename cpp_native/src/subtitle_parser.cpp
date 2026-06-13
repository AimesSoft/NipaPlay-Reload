/// @file subtitle_parser.cpp
/// @brief 字幕解析器实现 — ASS/SRT/SubViewer/MicroDVD + 编码检测/转换

#include "subtitle_parser.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <numeric>
#include <string>
#include <string_view>
#include <vector>
#include <optional>
#include <array>

// ──── 平台相关头文件 ────
#if defined(_WIN32)
    #define NP_WIN32 1
    #include <windows.h>
#elif defined(__ANDROID__)
    // Android NDK 不含 iconv，仅支持内建 UTF-8/UTF-16 解码
    #define NP_ANDROID 1
#else
    #define NP_POSIX 1
    #include <iconv.h>
    #include <cerrno>
#endif

namespace nipaplay::native {

// ──── 内建回退编码列表（与 Dart _fallbackEncodings 对应）────
static constexpr std::array fallback_encodings{
    "utf-16le", "utf-16be", "gb18030", "gbk",
    "big5", "cp950", "big5-hkscs", "shift_jis",
    "euc-kr", "windows-1252", "iso-8859-1",
};

// ════════════════════════════════════════════════════════════════
//  公共 API
// ════════════════════════════════════════════════════════════════

SubtitleParseOutput SubtitleParser::parseBytes(
    const uint8_t* data, int32_t len,
    std::string_view hint_path)
{
    SubtitleParseOutput output;

    if (!data || len <= 0) [[unlikely]] {
        output.detected_encoding = "utf-8";
        return output;
    }

    // ── 阶段 1：编码检测 + 解码为 UTF-8 文本 ──
    std::string utf8_text;
    std::string used_encoding;

    // 1a) BOM 检测
    if (auto bom = detectBomEncoding(data, len)) {
        bool strip = true;
        if (auto decoded = convertToUtf8(data, len, *bom, strip)) {
            utf8_text = std::move(*decoded);
            used_encoding = *bom;
        }
    }

    // 1b) UTF-8 验证（严格模式）
    if (utf8_text.empty() && isValidUtf8(data, len)) {
        utf8_text.assign(reinterpret_cast<const char*>(data),
                         static_cast<size_t>(len));
        used_encoding = "utf-8";
    }

    // 1c) 综合编码检测：回退列表 + 路径提示 + 评分
    if (utf8_text.empty()) {
        if (auto enc = detectEncoding(data, len, hint_path)) {
            if (auto decoded = convertToUtf8(data, len, *enc)) {
                utf8_text = std::move(*decoded);
                used_encoding = *enc;
            }
        }
    }

    // 1d) 最终回退：latin1 总能解码（每个字节 < 256）
    // 但在 Android 上，如果编码转换失败（convertToUtf8 返回 nullopt），
    // 原始 GBK/Big5/Shift-JIS 字节不是有效 latin1，强制解码会导致
    // 格式检测匹配但文本乱码，且 Dart 不会 fallback 到 charset_converter。
    // 因此 Android 上应返回空结果，让 Dart 侧处理。
    if (utf8_text.empty()) {
#if defined(__ANDROID__)
        // Android: 无 iconv，非 UTF-8 文件应交由 Dart charset_converter 处理
        output.entries = {};
        output.detected_encoding = used_encoding.empty() ? "unknown" : used_encoding;
        return output;
#else
        utf8_text.assign(reinterpret_cast<const char*>(data),
                         static_cast<size_t>(len));
        // 替换可疑的控制字符
        std::replace_if(utf8_text.begin(), utf8_text.end(),
            [](char c) { return static_cast<uint8_t>(c) < 0x09 ||
                                (static_cast<uint8_t>(c) > 0x0D &&
                                 static_cast<uint8_t>(c) < 0x20); },
            '?');
        used_encoding = "latin1";
#endif
    }

    output.detected_encoding = used_encoding;

    // ── 阶段 2：格式检测 ──
    output.format = detectFormat(utf8_text, hint_path);

    // ── 阶段 3：按格式解析 ──
    switch (output.format) {
        using enum SubtitleFormat;
        case ASS:
            output.entries = parseAss(utf8_text);
            break;
        case SRT:
            output.entries = parseSrt(utf8_text);
            break;
        case SubViewer:
            output.entries = parseSubViewer(utf8_text);
            break;
        case MicroDVD:
            output.entries = parseMicrodvd(utf8_text);
            break;
        case Unknown:
        default:
            break;
    }

    return output;
}

// ════════════════════════════════════════════════════════════════
//  格式检测
// ════════════════════════════════════════════════════════════════

SubtitleFormat SubtitleParser::detectFormat(
    std::string_view content, std::string_view hint_path)
{
    // 内容特征检测（优先于扩展名）
    // ASS: [Events] 段头 或 Dialogue: 行
    if (content.find("[Events]") != std::string_view::npos) {
        return SubtitleFormat::ASS;
    }
    // 逐行检查 Dialogue: （避免在文本内容中误匹配）
    for (size_t pos = 0; pos < content.size(); ) {
        auto eol = content.find('\n', pos);
        auto line = content.substr(pos,
            eol == std::string_view::npos ? std::string_view::npos : eol - pos);
        // 去除 \r
        if (!line.empty() && line.back() == '\r') {
            line.remove_suffix(1);
        }
        // 左 trim
        while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) {
            line.remove_prefix(1);
        }
        if (line.starts_with("Dialogue:")) {
            return SubtitleFormat::ASS;
        }
        if (eol == std::string_view::npos) break;
        pos = eol + 1;
    }

    // SRT: 时间模式 "HH:MM:SS,mmm --> HH:MM:SS,mmm"
    if (content.find("-->") != std::string_view::npos) {
        // 区分 SRT 和 SubViewer：SRT 用 "-->"，SubViewer 用 ","
        // 含 "-->" 且含 时间模式 → SRT
        // 简化：有 "-->" 就当 SRT（SubViewer 不用 -->）
        for (size_t pos = 0; pos < content.size(); ) {
            auto eol = content.find('\n', pos);
            auto line = content.substr(pos,
                eol == std::string_view::npos ? std::string_view::npos : eol - pos);
            if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
            if (line.find("-->") != std::string_view::npos) {
                // 验证两侧有时间格式
                if (line.find(':') != std::string_view::npos) {
                    return SubtitleFormat::SRT;
                }
            }
            if (eol == std::string_view::npos) break;
            pos = eol + 1;
        }
    }

    // SubViewer: 时间模式 "HH:MM:SS,mmm,HH:MM:SS,mmm"（逗号分隔，无 -->）
    for (size_t pos = 0; pos < content.size(); ) {
        auto eol = content.find('\n', pos);
        auto line = content.substr(pos,
            eol == std::string_view::npos ? std::string_view::npos : eol - pos);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) {
            line.remove_prefix(1);
        }
        // SubViewer: 数字开头，含逗号分隔的两个时间
        // 简单检测：行匹配 \d{1,2}:\d{2}:\d{2}[.,]\d{1,3},\s*\d{1,2}:\d{2}:\d{2}
        if (!line.empty() && line[0] >= '0' && line[0] <= '9') {
            // 查找两个时间用逗号分隔的模式
            auto comma = line.find(',');
            if (comma != std::string_view::npos) {
                auto after = line.substr(comma + 1);
                while (!after.empty() && after.front() == ' ') after.remove_prefix(1);
                if (!after.empty() && after[0] >= '0' && after[0] <= '9' &&
                    after.find(':') != std::string_view::npos) {
                    // 前后都有冒号 → 时间格式 → SubViewer
                    return SubtitleFormat::SubViewer;
                }
            }
        }
        if (eol == std::string_view::npos) break;
        pos = eol + 1;
    }

    // MicroDVD: {startframe}{endframe}text
    for (size_t pos = 0; pos < content.size(); ) {
        auto eol = content.find('\n', pos);
        auto line = content.substr(pos,
            eol == std::string_view::npos ? std::string_view::npos : eol - pos);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) {
            line.remove_prefix(1);
        }
        if (line.starts_with('{')) {
            // 验证 {digits}{digits} 模式
            auto close1 = line.find('}');
            if (close1 != std::string_view::npos && close1 + 1 < line.size()
                && line[close1 + 1] == '{') {
                auto close2 = line.find('}', close1 + 2);
                if (close2 != std::string_view::npos) {
                    // 检查括号内是否为数字
                    auto inner1 = line.substr(1, close1 - 1);
                    auto inner2 = line.substr(close1 + 2, close2 - close1 - 2);
                    bool all_digit1 = !inner1.empty() &&
                        std::all_of(inner1.begin(), inner1.end(),
                            [](char c) { return c >= '0' && c <= '9'; });
                    bool all_digit2 = !inner2.empty() &&
                        std::all_of(inner2.begin(), inner2.end(),
                            [](char c) { return c >= '0' && c <= '9'; });
                    if (all_digit1 && all_digit2) {
                        return SubtitleFormat::MicroDVD;
                    }
                }
            }
        }
        if (eol == std::string_view::npos) break;
        pos = eol + 1;
    }

    // 扩展名回退
    if (!hint_path.empty()) {
        // 转小写（简单 ASCII）
        auto lower = std::string(hint_path);
        std::transform(lower.begin(), lower.end(), lower.begin(),
            [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

        if (lower.ends_with(".ass") || lower.ends_with(".ssa")) {
            return SubtitleFormat::ASS;
        }
        if (lower.ends_with(".srt")) {
            return SubtitleFormat::SRT;
        }
        if (lower.ends_with(".sub")) {
            return SubtitleFormat::SubViewer;
        }
        if (lower.ends_with(".dvdsub") || lower.ends_with(".microdvd")) {
            return SubtitleFormat::MicroDVD;
        }
    }

    return SubtitleFormat::Unknown;
}

// ════════════════════════════════════════════════════════════════
//  ASS 解析器（状态机，无正则）
// ════════════════════════════════════════════════════════════════

std::vector<SubtitleEntry> SubtitleParser::parseAss(std::string_view content) {
    std::vector<SubtitleEntry> entries;
    entries.reserve(256);

    bool in_events = false;
    std::vector<std::string> format_fields;  // Format: 行的字段名
    std::vector<std::string_view> parts_buf; // 逗号分割复用缓冲

    // 逐行扫描
    for (size_t pos = 0; pos < content.size(); ) {
        auto eol = content.find('\n', pos);
        auto line = content.substr(pos,
            eol == std::string_view::npos ? std::string_view::npos : eol - pos);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);

        // 右 trim 空白
        while (!line.empty() && (line.back() == ' ' || line.back() == '\t')) {
            line.remove_suffix(1);
        }
        // 左 trim 空白
        while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) {
            line.remove_prefix(1);
        }

        // 检查段头
        if (line == "[Events]") {
            in_events = true;
            if (eol == std::string_view::npos) break;
            pos = eol + 1;
            continue;
        }
        // 新段开始 → 退出 Events
        if (in_events && line.starts_with('[') && line.ends_with(']')) {
            break;
        }
        if (!in_events) {
            if (eol == std::string_view::npos) break;
            pos = eol + 1;
            continue;
        }

        // 解析 Format: 行
        if (line.starts_with("Format:")) {
            auto fmt_part = line.substr(7); // "Format:" 长度
            while (!fmt_part.empty() && fmt_part.front() == ' ') {
                fmt_part.remove_prefix(1);
            }
            format_fields.clear();
            // 逗号分割，trim 空格
            for (size_t i = 0; i < fmt_part.size(); ) {
                auto comma = fmt_part.find(',', i);
                auto field = fmt_part.substr(i,
                    comma == std::string_view::npos ? std::string_view::npos : comma - i);
                // trim
                while (!field.empty() && field.front() == ' ') field.remove_prefix(1);
                while (!field.empty() && field.back() == ' ') field.remove_suffix(1);
                format_fields.emplace_back(field);
                if (comma == std::string_view::npos) break;
                i = comma + 1;
            }
            if (eol == std::string_view::npos) break;
            pos = eol + 1;
            continue;
        }

        // 解析 Dialogue: 行
        if (line.starts_with("Dialogue:")) {
            auto dial_part = line.substr(9); // "Dialogue:" 长度
            while (!dial_part.empty() && dial_part.front() == ' ') {
                dial_part.remove_prefix(1);
            }

            parts_buf.clear();
            splitDialogueLine(dial_part, parts_buf);

            if (format_fields.empty() || parts_buf.size() < format_fields.size()) {
                if (eol == std::string_view::npos) break;
                pos = eol + 1;
                continue;
            }

            // 字段名 → 值 映射（使用结构化绑定风格遍历）
            // 直接按索引查找关键字段
            int32_t start_ms = 0, end_ms = 0;
            std::string_view text_sv, style_sv, name_sv, layer_sv, effect_sv;

            for (size_t i = 0; i < format_fields.size(); ++i) {
                const auto& fname = format_fields[i];
                const auto val = (i < parts_buf.size()) ? parts_buf[i] : std::string_view{};

                if (fname == "Start")          start_ms = parseTimeToMs(val);
                else if (fname == "End")        end_ms   = parseTimeToMs(val);
                else if (fname == "Text")       text_sv  = val;
                else if (fname == "Style")      style_sv = val;
                else if (fname == "Name")       name_sv  = val;
                else if (fname == "Layer")      layer_sv = val;
                else if (fname == "Effect")     effect_sv = val;
            }

            auto cleaned = cleanAssText(text_sv);
            if (cleaned.empty()) {
                if (eol == std::string_view::npos) break;
                pos = eol + 1;
                continue;
            }

            entries.push_back({
                .start_time_ms = start_ms,
                .end_time_ms   = end_ms,
                .content       = std::move(cleaned),
                .style         = style_sv.empty() ? "Default" : std::string(style_sv),
                .layer         = layer_sv.empty() ? "0" : std::string(layer_sv),
                .name          = std::string(name_sv),
                .effect        = std::string(effect_sv),
            });
        }

        if (eol == std::string_view::npos) break;
        pos = eol + 1;
    }

    // 按开始时间排序
    std::sort(entries.begin(), entries.end(),
        [](const SubtitleEntry& a, const SubtitleEntry& b) {
            return a.start_time_ms < b.start_time_ms;
        });

    return entries;
}

// ════════════════════════════════════════════════════════════════
//  SRT 解析器（状态机，无正则）
// ════════════════════════════════════════════════════════════════

std::vector<SubtitleEntry> SubtitleParser::parseSrt(std::string_view content) {
    std::vector<SubtitleEntry> entries;
    entries.reserve(128);

    // 按空行分块
    size_t pos = 0;
    while (pos < content.size()) {
        // 跳过前导空行
        while (pos < content.size()) {
            auto c = content[pos];
            if (c == '\n' || c == '\r') ++pos;
            else break;
        }
        if (pos >= content.size()) break;

        // 收集一个块直到空行
        std::string block;
        while (pos < content.size()) {
            auto eol = content.find('\n', pos);
            auto line = content.substr(pos,
                eol == std::string_view::npos ? std::string_view::npos : eol - pos);
            if (!line.empty() && line.back() == '\r') line.remove_suffix(1);

            // 空行 → 块结束
            auto trimmed = line;
            while (!trimmed.empty() && (trimmed.front() == ' ' || trimmed.front() == '\t'))
                trimmed.remove_prefix(1);
            while (!trimmed.empty() && (trimmed.back() == ' ' || trimmed.back() == '\t'))
                trimmed.remove_suffix(1);
            if (trimmed.empty()) {
                if (eol == std::string_view::npos) break;
                pos = eol + 1;
                break;
            }

            if (!block.empty()) block += '\n';
            block += std::string(line);
            if (eol == std::string_view::npos) {
                pos = content.size();  // 消费到末尾，防止外层 while 无限循环
                break;
            }
            pos = eol + 1;
        }

        if (block.empty()) continue;

        // 解析块：[序号行] → 时间行 → 内容行
        auto first_nl = block.find('\n');
        auto line1 = (first_nl == std::string::npos)
            ? std::string_view(block)
            : std::string_view(block).substr(0, first_nl);

        // 判断第一行是否为序号（纯数字）
        auto trimmed1 = line1;
        while (!trimmed1.empty() && trimmed1.front() == ' ') trimmed1.remove_prefix(1);
        while (!trimmed1.empty() && trimmed1.back() == ' ') trimmed1.remove_suffix(1);

        bool is_index = !trimmed1.empty() &&
            std::all_of(trimmed1.begin(), trimmed1.end(),
                [](char c) { return c >= '0' && c <= '9'; });

        std::string_view time_line;
        size_t content_start = 0;

        if (is_index) {
            // 第二行为时间行
            if (first_nl == std::string::npos) continue;
            auto second_nl = block.find('\n', first_nl + 1);
            time_line = (second_nl == std::string::npos)
                ? std::string_view(block).substr(first_nl + 1)
                : std::string_view(block).substr(first_nl + 1, second_nl - first_nl - 1);
            content_start = (second_nl == std::string::npos)
                ? std::string::npos : second_nl + 1;
        } else {
            // 第一行就是时间行（某些 SRT 变体无序号）
            time_line = line1;
            content_start = (first_nl == std::string::npos)
                ? std::string::npos : first_nl + 1;
        }

        // 解析时间行："H:MM:SS,mmm --> H:MM:SS,mmm"
        auto arrow = time_line.find("-->");
        if (arrow == std::string_view::npos) continue;

        auto start_str = time_line.substr(0, arrow);
        auto end_str   = time_line.substr(arrow + 3);
        // trim
        while (!start_str.empty() && start_str.back() == ' ') start_str.remove_suffix(1);
        while (!end_str.empty() && end_str.front() == ' ') end_str.remove_prefix(1);

        int32_t start_ms = parseTimeToMs(start_str);
        int32_t end_ms   = parseTimeToMs(end_str);
        if (end_ms <= start_ms) continue;

        // 内容行
        std::string text;
        if (content_start != std::string::npos) {
            text = block.substr(content_start);
        }
        // trim
        while (!text.empty() && (text.back() == '\n' || text.back() == '\r'
                                 || text.back() == ' ' || text.back() == '\t'))
            text.pop_back();
        while (!text.empty() && (text.front() == ' ' || text.front() == '\t'))
            text.erase(text.begin());

        if (text.empty()) continue;

        entries.push_back({
            .start_time_ms = start_ms,
            .end_time_ms   = end_ms,
            .content       = std::move(text),
            .style         = "Default",
            .layer         = "0",
            .name          = {},
            .effect        = {},
        });
    }

    std::sort(entries.begin(), entries.end(),
        [](const SubtitleEntry& a, const SubtitleEntry& b) {
            return a.start_time_ms < b.start_time_ms;
        });

    return entries;
}

// ════════════════════════════════════════════════════════════════
//  SubViewer 解析器
// ════════════════════════════════════════════════════════════════

std::vector<SubtitleEntry> SubtitleParser::parseSubViewer(std::string_view content) {
    std::vector<SubtitleEntry> entries;
    entries.reserve(128);

    size_t pos = 0;
    while (pos < content.size()) {
        auto eol = content.find('\n', pos);
        auto line = content.substr(pos,
            eol == std::string_view::npos ? std::string_view::npos : eol - pos);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        while (!line.empty() && (line.front() == ' ' || line.front() == '\t'))
            line.remove_prefix(1);

        // 查找时间行：HH:MM:SS,mmm,HH:MM:SS,mmm
        if (!line.empty() && line[0] >= '0' && line[0] <= '9') {
            auto comma = line.find(',');
            if (comma != std::string_view::npos) {
                auto start_str = line.substr(0, comma);
                auto rest = line.substr(comma + 1);
                while (!rest.empty() && rest.front() == ' ') rest.remove_prefix(1);

                if (!rest.empty() && rest[0] >= '0' && rest[0] <= '9') {
                    // end_str 可能到行尾或下一个逗号
                    auto end_str = rest;
                    auto comma2 = rest.find(',');
                    if (comma2 != std::string_view::npos) {
                        end_str = rest.substr(0, comma2);
                    }

                    int32_t start_ms = parseTimeToMs(start_str);
                    int32_t end_ms   = parseTimeToMs(end_str);

                    if (eol != std::string_view::npos) pos = eol + 1;
                    else break;

                    // 收集后续文本行（直到空行）
                    std::string text;
                    while (pos < content.size()) {
                        auto neol = content.find('\n', pos);
                        auto nline = content.substr(pos,
                            neol == std::string_view::npos
                                ? std::string_view::npos : neol - pos);
                        if (!nline.empty() && nline.back() == '\r') nline.remove_suffix(1);
                        auto trimmed = nline;
                        while (!trimmed.empty() && (trimmed.front() == ' '
                                                    || trimmed.front() == '\t'))
                            trimmed.remove_prefix(1);
                        while (!trimmed.empty() && (trimmed.back() == ' '
                                                    || trimmed.back() == '\t'))
                            trimmed.remove_suffix(1);

                        if (trimmed.empty()) {
                            if (neol == std::string_view::npos) {
                                pos = content.size();
                                break;
                            }
                            pos = neol + 1;
                            break;
                        }
                        if (!text.empty()) text += '\n';
                        text += std::string(nline);
                        if (neol == std::string_view::npos) {
                            pos = content.size();
                            break;
                        }
                        pos = neol + 1;
                    }

                    while (!text.empty() && (text.back() == '\n' || text.back() == '\r'
                                             || text.back() == ' '))
                        text.pop_back();

                    if (!text.empty() && end_ms > start_ms) {
                        entries.push_back({
                            .start_time_ms = start_ms,
                            .end_time_ms   = end_ms,
                            .content       = std::move(text),
                            .style         = "Default",
                            .layer         = "0",
                            .name          = {},
                            .effect        = {},
                        });
                    }
                    continue;
                }
            }
        }

        if (eol == std::string_view::npos) break;
        pos = eol + 1;
    }

    std::sort(entries.begin(), entries.end(),
        [](const SubtitleEntry& a, const SubtitleEntry& b) {
            return a.start_time_ms < b.start_time_ms;
        });

    return entries;
}

// ════════════════════════════════════════════════════════════════
//  MicroDVD 解析器
// ════════════════════════════════════════════════════════════════

std::vector<SubtitleEntry> SubtitleParser::parseMicrodvd(
    std::string_view content, double default_fps)
{
    std::vector<SubtitleEntry> entries;
    entries.reserve(128);
    double fps = 0.0;

    for (size_t pos = 0; pos < content.size(); ) {
        auto eol = content.find('\n', pos);
        auto line = content.substr(pos,
            eol == std::string_view::npos ? std::string_view::npos : eol - pos);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        while (!line.empty() && (line.front() == ' ' || line.front() == '\t'))
            line.remove_prefix(1);

        // 匹配 {startframe}{endframe}payload
        if (line.starts_with('{')) {
            auto close1 = line.find('}');
            if (close1 != std::string_view::npos && close1 + 1 < line.size()
                && line[close1 + 1] == '{') {
                auto close2 = line.find('}', close1 + 2);
                if (close2 != std::string_view::npos) {
                    auto inner1 = line.substr(1, close1 - 1);
                    auto inner2 = line.substr(close1 + 2, close2 - close1 - 2);
                    auto payload = line.substr(close2 + 1);

                    int32_t start_frame = 0, end_frame = 0;
                    // 数字解析
                    if (!inner1.empty())
                        start_frame = parseUint(inner1);
                    if (!inner2.empty())
                        end_frame = parseUint(inner2);

                    // FPS 行检测
                    if ((start_frame == 0 && end_frame == 0) ||
                        (start_frame == 1 && end_frame == 1)) {
                        // 尝试解析 FPS
                        auto fps_str = payload;
                        // 去除 {|} 标记
                        while (!fps_str.empty() && fps_str.front() == '{') {
                            auto cb = fps_str.find('}');
                            if (cb == std::string_view::npos) break;
                            fps_str.remove_prefix(cb + 1);
                        }
                        // 逗号→点
                        std::string fps_norm(fps_str);
                        std::replace(fps_norm.begin(), fps_norm.end(), ',', '.');
                        // trim
                        while (!fps_norm.empty() && (fps_norm.back() == '\n'
                                                     || fps_norm.back() == '\r'
                                                     || fps_norm.back() == ' '))
                            fps_norm.pop_back();
                        char* end = nullptr;
                        double parsed = std::strtod(fps_norm.c_str(), &end);
                        if (end != fps_norm.c_str() && parsed > 1.0) {
                            fps = parsed;
                        }
                    } else {
                        auto used_fps = fps > 0 ? fps : default_fps;
                        if (used_fps <= 0) {
                            if (eol == std::string_view::npos) break;
                            pos = eol + 1;
                            continue;
                        }

                        int32_t start_ms = static_cast<int32_t>(
                            (start_frame / used_fps) * 1000.0);
                        int32_t end_ms = static_cast<int32_t>(
                            (end_frame / used_fps) * 1000.0);
                        if (end_ms <= start_ms) {
                            if (eol == std::string_view::npos) break;
                            pos = eol + 1;
                            continue;
                        }

                        // 清理 payload：| → 换行，{xxx} 标记移除
                        std::string text(payload);
                        // 移除 {xxx} 样式标记
                        std::string cleaned;
                        cleaned.reserve(text.size());
                        for (size_t i = 0; i < text.size(); ) {
                            if (text[i] == '{') {
                                auto cb = text.find('}', i);
                                if (cb != std::string::npos) {
                                    i = cb + 1;
                                    continue;
                                }
                            }
                            if (text[i] == '|') {
                                cleaned += '\n';
                                ++i;
                            } else {
                                cleaned += text[i];
                                ++i;
                            }
                        }
                        // trim
                        while (!cleaned.empty() && (cleaned.back() == '\n'
                                                    || cleaned.back() == '\r'
                                                    || cleaned.back() == ' '))
                            cleaned.pop_back();
                        while (!cleaned.empty() && (cleaned.front() == ' '
                                                    || cleaned.front() == '\t'))
                            cleaned.erase(cleaned.begin());

                        if (!cleaned.empty()) {
                            entries.push_back({
                                .start_time_ms = start_ms,
                                .end_time_ms   = end_ms,
                                .content       = std::move(cleaned),
                                .style         = "Default",
                                .layer         = "0",
                                .name          = {},
                                .effect        = {},
                            });
                        }
                    }
                }
            }
        }

        if (eol == std::string_view::npos) break;
        pos = eol + 1;
    }

    std::sort(entries.begin(), entries.end(),
        [](const SubtitleEntry& a, const SubtitleEntry& b) {
            return a.start_time_ms < b.start_time_ms;
        });

    return entries;
}

// ════════════════════════════════════════════════════════════════
//  编码检测
// ════════════════════════════════════════════════════════════════

std::optional<std::string> SubtitleParser::detectBomEncoding(
    const uint8_t* data, int32_t len)
{
    if (len >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
        return "utf-8";
    }
    if (len >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
        return "utf-16le";
    }
    if (len >= 2 && data[0] == 0xFE && data[1] == 0xFF) {
        return "utf-16be";
    }
    return std::nullopt;
}

bool SubtitleParser::isValidUtf8(const uint8_t* data, int32_t len) noexcept {
    int32_t i = 0;
    while (i < len) {
        auto byte = data[i];
        int32_t cont_bytes;

        if (byte <= 0x7F) {
            cont_bytes = 0;
        } else if ((byte & 0xE0) == 0xC0) {   // 2-byte: C0-DF
            if (byte < 0xC2) [[unlikely]] return false;  // C0,C1 是过长编码
            cont_bytes = 1;
        } else if ((byte & 0xF0) == 0xE0) {   // 3-byte
            cont_bytes = 2;
        } else if ((byte & 0xF8) == 0xF0) {   // 4-byte
            cont_bytes = 3;
        } else {
            return false;  // 非法首字节 (0x80-0xBF, 0xF5-0xFF)
        }

        if (i + cont_bytes >= len) [[unlikely]] return false;

        for (int32_t j = 1; j <= cont_bytes; ++j) {
            if ((data[i + j] & 0xC0) != 0x80) [[unlikely]] return false;
        }

        // 过长编码检测
        if constexpr (true) {  // always check
            if (cont_bytes == 2) {
                auto cp = ((data[i] & 0x0F) << 12) |
                          ((data[i+1] & 0x3F) << 6) |
                          (data[i+2] & 0x3F);
                if (cp < 0x0800) [[unlikely]] return false;
                // 代理对范围 (UTF-8 编码中不应出现)
                if (cp >= 0xD800 && cp <= 0xDFFF) [[unlikely]] return false;
            }
            if (cont_bytes == 3) {
                auto cp = ((data[i] & 0x07) << 18) |
                          ((data[i+1] & 0x3F) << 12) |
                          ((data[i+2] & 0x3F) << 6) |
                          (data[i+3] & 0x3F);
                if (cp < 0x10000 || cp > 0x10FFFF) [[unlikely]] return false;
            }
        }

        i += cont_bytes + 1;
    }
    return true;
}

std::optional<std::string> SubtitleParser::detectEncoding(
    const uint8_t* data, int32_t len, std::string_view hint_path)
{
    // 快速排除：二进制数据
    if (looksBinary(data, len)) {
        if (!looksLikeUtf16(data, len)) {
            return std::nullopt;
        }
    }

    auto candidates = buildEncodingCandidates(hint_path);
    const bool looks_utf16 = looksLikeUtf16(data, len);

    // 移除不匹配的 UTF-16 编码
    if (!looks_utf16) {
        candidates.erase(
            std::remove_if(candidates.begin(), candidates.end(),
                [](const std::string& e) { return isUtf16Encoding(e); }),
            candidates.end());
    }

    std::string best_encoding;
    double best_score = -1e9;

    for (const auto& encoding : candidates) {
        auto decoded = convertToUtf8(data, len, encoding);
        if (!decoded || decoded->empty()) continue;
        if (!looksLikeText(*decoded)) continue;

        auto format = detectFormat(*decoded, hint_path);
        double score = scoreDecodedText(*decoded, hint_path, encoding, format);
        if (score > best_score) {
            best_score = score;
            best_encoding = encoding;
        }
    }

    if (best_encoding.empty()) return std::nullopt;
    return best_encoding;
}

// ════════════════════════════════════════════════════════════════
//  编码转换
// ════════════════════════════════════════════════════════════════

std::optional<std::string> SubtitleParser::convertToUtf8(
    const uint8_t* data, int32_t len,
    std::string_view encoding, bool strip_bom)
{
    auto lower = std::string(encoding);
    std::transform(lower.begin(), lower.end(), lower.begin(),
        [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    // 计算实际数据起始（跳过 BOM）
    int32_t offset = 0;
    if (strip_bom) {
        if (lower == "utf-8" && len >= 3 &&
            data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
            offset = 3;
        } else if ((lower == "utf-16le" || lower == "utf-16be") && len >= 2) {
            offset = 2;
        }
    }
    const uint8_t* actual_data = data + offset;
    const int32_t actual_len = len - offset;

    // UTF-8 直接返回
    if (lower == "utf-8" || lower == "utf8") {
        if (!isValidUtf8(actual_data, actual_len)) return std::nullopt;
        return std::string(reinterpret_cast<const char*>(actual_data),
                           static_cast<size_t>(actual_len));
    }

    // UTF-16 手动解码
    if (lower == "utf-16le" || lower == "utf16le") {
        return decodeUtf16(actual_data, actual_len, true);
    }
    if (lower == "utf-16be" || lower == "utf16be") {
        return decodeUtf16(actual_data, actual_len, false);
    }

    // ── 平台相关编码转换 ──
#if NP_WIN32
    // Windows: 使用 MultiByteToWideChar + WideCharToMultiByte
    uint32_t codepage = encodingToCodepage(lower);
    if (codepage == 0) return std::nullopt;

    // Step 1: 多字节 → UTF-16 (wchar_t)
    int wlen = MultiByteToWideChar(
        codepage, MB_ERR_INVALID_CHARS,
        reinterpret_cast<const char*>(actual_data), actual_len,
        nullptr, 0);
    if (wlen <= 0) [[unlikely]] return std::nullopt;

    auto wbuf = std::wstring{};
    wbuf.resize(static_cast<size_t>(wlen));
    MultiByteToWideChar(
        codepage, MB_ERR_INVALID_CHARS,
        reinterpret_cast<const char*>(actual_data), actual_len,
        wbuf.data(), wlen);

    // Step 2: UTF-16 → UTF-8
    int u8len = WideCharToMultiByte(
        CP_UTF8, 0,
        wbuf.data(), wlen,
        nullptr, 0,
        nullptr, nullptr);
    if (u8len <= 0) [[unlikely]] return std::nullopt;

    std::string result;
    result.resize(static_cast<size_t>(u8len));
    WideCharToMultiByte(
        CP_UTF8, 0,
        wbuf.data(), wlen,
        result.data(), u8len,
        nullptr, nullptr);

    return result;

#elif NP_POSIX
    // POSIX (Linux/macOS/iOS): 使用 iconv
    auto iconv_name = encodingToIconvName(encoding);
    if (iconv_name.empty()) return std::nullopt;

    iconv_t cd = iconv_open("UTF-8", iconv_name.c_str());
    if (cd == reinterpret_cast<iconv_t>(-1)) return std::nullopt;

    // RAII guard
    struct IconvCloser {
        iconv_t cd;
        ~IconvCloser() { if (cd != reinterpret_cast<iconv_t>(-1)) iconv_close(cd); }
    } closer{cd};

    size_t inbytes_left = static_cast<size_t>(actual_len);
    size_t outbytes_left = static_cast<size_t>(actual_len) * 4 + 4; // 最多 4x 扩展
    std::string result(outbytes_left, '\0');

    char* in_ptr = const_cast<char*>(reinterpret_cast<const char*>(actual_data));
    char* out_ptr = result.data();

    size_t ret = iconv(cd, &in_ptr, &inbytes_left, &out_ptr, &outbytes_left);
    if (ret == static_cast<size_t>(-1)) {
        if (errno == EILSEQ || errno == EINVAL) return std::nullopt;
        // E2BIG 不应该发生（输出缓冲区足够大）
        return std::nullopt;
    }

    result.resize(static_cast<size_t>(out_ptr - result.data()));
    return result;

#else
    // Android: 无 iconv，不支持非 UTF 编码转换
    // Dart 侧 fallback 到 charset_converter 处理
    return std::nullopt;
#endif
}

std::string SubtitleParser::decodeUtf16(
    const uint8_t* data, int32_t len, bool little_endian)
{
    if (len < 2) return {};

    const int32_t code_units = len / 2;
    std::string result;
    result.reserve(static_cast<size_t>(code_units) * 3); // UTF-8 最多 3 字节/字符

    for (int32_t i = 0; i < code_units; ++i) {
        char16_t unit;
        if (little_endian) {
            unit = static_cast<char16_t>(data[i*2] | (data[i*2+1] << 8));
        } else {
            unit = static_cast<char16_t>((data[i*2] << 8) | data[i*2+1]);
        }

        // 代理对处理
        if (unit >= 0xD800 && unit <= 0xDBFF) {
            // 高代理
            if (i + 1 >= code_units) break;
            char16_t low;
            if (little_endian) {
                low = static_cast<char16_t>(data[(i+1)*2] | (data[(i+1)*2+1] << 8));
            } else {
                low = static_cast<char16_t>((data[(i+1)*2] << 8) | data[(i+1)*2+1]);
            }
            if (low >= 0xDC00 && low <= 0xDFFF) {
                char32_t cp = 0x10000 +
                    ((static_cast<char32_t>(unit) - 0xD800) << 10) +
                    (static_cast<char32_t>(low) - 0xDC00);
                // 4 字节 UTF-8
                result += static_cast<char>(0xF0 | ((cp >> 18) & 0x07));
                result += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
                result += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                result += static_cast<char>(0x80 | (cp & 0x3F));
                ++i; // 跳过低代理
            } else {
                // 孤立高代理 → 跳过
            }
        } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
            // 孤立低代理 → 跳过
        } else {
            // BMP 字符 → UTF-8 编码
            if (unit <= 0x7F) {
                result += static_cast<char>(unit);
            } else if (unit <= 0x7FF) {
                result += static_cast<char>(0xC0 | ((unit >> 6) & 0x1F));
                result += static_cast<char>(0x80 | (unit & 0x3F));
            } else {
                result += static_cast<char>(0xE0 | ((unit >> 12) & 0x0F));
                result += static_cast<char>(0x80 | ((unit >> 6) & 0x3F));
                result += static_cast<char>(0x80 | (unit & 0x3F));
            }
        }
    }

    return result;
}

// ════════════════════════════════════════════════════════════════
//  文本质量评估
// ════════════════════════════════════════════════════════════════

bool SubtitleParser::looksLikeText(std::string_view text) {
    if (text.empty()) return true;
    const auto sample = text.length() > 2048 ? text.substr(0, 2048) : text;
    int32_t control = 0;
    for (size_t i = 0; i < sample.size(); ) {
        auto byte = static_cast<uint8_t>(sample[i]);
        char32_t cp = 0;
        int32_t cont;

        if (byte <= 0x7F) { cp = byte; cont = 0; }
        else if ((byte & 0xE0) == 0xC0) { cp = byte & 0x1F; cont = 1; }
        else if ((byte & 0xF0) == 0xE0) { cp = byte & 0x0F; cont = 2; }
        else if ((byte & 0xF8) == 0xF0) { cp = byte & 0x07; cont = 3; }
        else { cont = 0; cp = 0xFFFD; ++i; continue; }

        i++;
        bool valid = true;
        for (int32_t j = 0; j < cont && i < sample.size(); ++j, ++i) {
            auto cb = static_cast<uint8_t>(sample[i]);
            if ((cb & 0xC0) != 0x80) { valid = false; break; }
            cp = (cp << 6) | (cb & 0x3F);
        }
        if (!valid) { ++control; continue; }

        if (cp == 0xFFFD ||
            (cp < 0x09 || (cp > 0x0D && cp < 0x20))) {
            ++control;
        }
    }
    auto sample_len = static_cast<double>(sample.size());
    return sample_len == 0.0 || (control / sample_len) < 0.05;
}

bool SubtitleParser::looksBinary(const uint8_t* data, int32_t len) noexcept {
    if (len <= 0) return false;
    int32_t zero_count = 0;
    int32_t control_count = 0;
    for (int32_t i = 0; i < len; ++i) {
        if (data[i] == 0) ++zero_count;
        if (data[i] < 0x09 || (data[i] > 0x0D && data[i] < 0x20))
            ++control_count;
    }
    auto dlen = static_cast<double>(len);
    return (zero_count / dlen) > 0.1 || (control_count / dlen) > 0.3;
}

bool SubtitleParser::looksLikeUtf16(const uint8_t* data, int32_t len) noexcept {
    if (len < 4) return false;
    int32_t even_zeros = 0, odd_zeros = 0;
    int32_t even_count = 0, odd_count = 0;
    for (int32_t i = 0; i < len; ++i) {
        if (i % 2 == 0) {
            ++even_count;
            if (data[i] == 0) ++even_zeros;
        } else {
            ++odd_count;
            if (data[i] == 0) ++odd_zeros;
        }
    }
    auto even_ratio = even_count > 0 ? static_cast<double>(even_zeros) / even_count : 0.0;
    auto odd_ratio  = odd_count > 0 ? static_cast<double>(odd_zeros) / odd_count : 0.0;
    return even_ratio > 0.6 || odd_ratio > 0.6;
}

double SubtitleParser::scoreDecodedText(
    std::string_view text, std::string_view hint_path,
    std::string_view encoding, SubtitleFormat format)
{
    const auto sample = text.length() > 8192 ? text.substr(0, 8192) : text;
    int32_t total = 0, cjk = 0, ascii = 0, replacement = 0, control = 0, punct = 0;
    int32_t latin1_supp = 0;

    for (size_t i = 0; i < sample.size(); ) {
        auto byte = static_cast<uint8_t>(sample[i]);
        char32_t cp = 0;
        int32_t cont;

        if (byte <= 0x7F) { cp = byte; cont = 0; }
        else if ((byte & 0xE0) == 0xC0) { cp = byte & 0x1F; cont = 1; }
        else if ((byte & 0xF0) == 0xE0) { cp = byte & 0x0F; cont = 2; }
        else if ((byte & 0xF8) == 0xF0) { cp = byte & 0x07; cont = 3; }
        else { cont = 0; cp = 0xFFFD; ++i; ++total; ++replacement; continue; }

        i++;
        bool valid = true;
        for (int32_t j = 0; j < cont && i < sample.size(); ++j, ++i) {
            auto cb = static_cast<uint8_t>(sample[i]);
            if ((cb & 0xC0) != 0x80) { valid = false; break; }
            cp = (cp << 6) | (cb & 0x3F);
        }
        if (!valid) { ++total; ++replacement; continue; }

        ++total;
        if (cp == 0xFFFD) ++replacement;
        if (cp < 0x09 || (cp > 0x0D && cp < 0x20)) ++control;
        if (cp >= 0x20 && cp <= 0x7E) ++ascii;
        if (cp >= 0xA1 && cp <= 0xFF) ++latin1_supp;
        if (isCjkCodePoint(cp)) ++cjk;
        if (isCjkPunctuation(cp)) ++punct;
    }

    if (total == 0) return -1e9;

    auto dtotal = static_cast<double>(total);
    auto cjk_ratio    = cjk / dtotal;
    auto ascii_ratio  = ascii / dtotal;
    auto repl_ratio   = replacement / dtotal;
    auto ctrl_ratio   = control / dtotal;
    auto punct_ratio  = punct / dtotal;
    auto lat1_ratio   = latin1_supp / dtotal;

    double score = 0.0;
    if (format != SubtitleFormat::Unknown) score += 5.0;
    else score -= 2.0;

    score += cjk_ratio * 8.0;
    score += ascii_ratio * 2.0;
    score += punct_ratio * 2.0;
    score -= repl_ratio * 20.0;
    score -= ctrl_ratio * 12.0;

    if (lat1_ratio > 0.08 && cjk_ratio < 0.02) {
        score -= (lat1_ratio - 0.08) * 40.0;
    }
    auto lower_enc = std::string(encoding);
    std::transform(lower_enc.begin(), lower_enc.end(), lower_enc.begin(),
        [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (lower_enc == "latin1" && lat1_ratio > 0.06 && cjk_ratio < 0.02) {
        score -= 8.0;
    }

    score += scoreEncodingHint(hint_path, encoding);
    return score;
}

double SubtitleParser::scoreEncodingHint(
    std::string_view hint_path, std::string_view encoding)
{
    auto lower_path = std::string(hint_path);
    std::transform(lower_path.begin(), lower_path.end(), lower_path.begin(),
        [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    auto lower_enc = std::string(encoding);
    std::transform(lower_enc.begin(), lower_enc.end(), lower_enc.begin(),
        [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    double score = 0.0;

    // Big5 提示
    if (lower_path.find("big5") != std::string::npos ||
        lower_path.find("繁体") != std::string::npos ||
        lower_path.find("cht") != std::string::npos ||
        lower_path.find("traditional") != std::string::npos) {
        if (lower_enc.find("big5") != std::string::npos) score += 1.5;
    }

    // GBK 提示
    if (lower_path.find("gbk") != std::string::npos ||
        lower_path.find("gb2312") != std::string::npos ||
        lower_path.find("gb18030") != std::string::npos ||
        lower_path.find("简体") != std::string::npos ||
        lower_path.find("chs") != std::string::npos) {
        if (lower_enc.find("gb") != std::string::npos) score += 1.5;
    }

    return score;
}

// ════════════════════════════════════════════════════════════════
//  ASS 辅助
// ════════════════════════════════════════════════════════════════

std::string SubtitleParser::cleanAssText(std::string_view text) {
    std::string result;
    result.reserve(text.size());

    size_t i = 0;
    while (i < text.size()) {
        // 移除 {\xxx} 样式标记
        if (text[i] == '{') {
            // 查找配对的 }
            auto close = text.find('}', i);
            if (close != std::string_view::npos) {
                // 检查是否为样式标记（以 \ 开头）
                auto inner = text.substr(i + 1, close - i - 1);
                if (!inner.empty() && inner[0] == '\\') {
                    i = close + 1;
                    continue;
                }
                // 非样式标记的花括号 → 保留
            }
        }

        // \N → 换行
        if (text[i] == '\\' && i + 1 < text.size() && text[i+1] == 'N') {
            result += '\n';
            i += 2;
            continue;
        }
        // \n → 换行（ASS 中也是换行）
        if (text[i] == '\\' && i + 1 < text.size() && text[i+1] == 'n') {
            result += '\n';
            i += 2;
            continue;
        }

        result += text[i];
        ++i;
    }

    // trim
    while (!result.empty() && (result.back() == ' ' || result.back() == '\t'))
        result.pop_back();
    while (!result.empty() && (result.front() == ' ' || result.front() == '\t'))
        result.erase(result.begin());

    return result;
}

void SubtitleParser::splitDialogueLine(
    std::string_view line, std::vector<std::string_view>& out)
{
    // ASS Dialogue 行的前 9 个字段按逗号分割，最后一个字段(Text)保留所有内容
    // 字段: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    // 前 8 个逗号分割，第 9 个逗号后全部为 Text

    int32_t comma_count = 0;
    size_t last_comma = 0;

    for (size_t i = 0; i < line.size(); ++i) {
        if (line[i] == ',' && comma_count < 8) {
            out.push_back(line.substr(last_comma, i - last_comma));
            last_comma = i + 1;
            ++comma_count;
        }
    }

    // 第 9 个字段 (Effect) + 最后一个字段 (Text)
    if (comma_count == 8) {
        // 查找第 9 个逗号
        auto next_comma = line.find(',', last_comma);
        if (next_comma != std::string_view::npos) {
            out.push_back(line.substr(last_comma, next_comma - last_comma));
            out.push_back(line.substr(next_comma + 1));
        } else {
            out.push_back(line.substr(last_comma));
        }
    } else if (last_comma < line.size()) {
        out.push_back(line.substr(last_comma));
    }
}

// ════════════════════════════════════════════════════════════════
//  编码名处理
// ════════════════════════════════════════════════════════════════

std::optional<std::string> SubtitleParser::normalizeEncodingName(std::string_view raw) {
    auto lower = std::string(raw);
    std::transform(lower.begin(), lower.end(), lower.begin(),
        [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    if (lower.empty()) return std::nullopt;
    if (lower.find("unknown") != std::string::npos ||
        lower.find("binary") != std::string::npos)
        return std::nullopt;

    if (lower == "ascii") return "utf-8";
    if (lower.starts_with("utf-8") || lower == "utf8") return "utf-8";
    if (lower == "utf-16le" || lower == "utf16le") return "utf-16le";
    if (lower == "utf-16be" || lower == "utf16be") return "utf-16be";
    if (lower == "big5" || lower == "big-5") return "big5";
    if (lower == "big5-hkscs" || lower == "big5hkscs") return "big5-hkscs";
    if (lower == "cp950" || lower == "windows-950") return "cp950";
    if (lower == "gb18030") return "gb18030";
    if (lower == "gbk" || lower == "cp936" || lower == "windows-936") return "gbk";
    if (lower == "gb2312") return "gb18030";
    if (lower == "shift_jis" || lower == "shift-jis" || lower == "sjis"
        || lower == "windows-31j") return "shift_jis";
    if (lower == "euc-kr" || lower == "euckr") return "euc-kr";
    if (lower == "iso-8859-1" || lower == "iso_8859-1" || lower == "latin1")
        return "iso-8859-1";
    if (lower == "windows-1252" || lower == "cp1252") return "windows-1252";

    return std::nullopt;
}

std::vector<std::string> SubtitleParser::buildEncodingCandidates(
    std::string_view hint_path)
{
    auto candidates = std::vector<std::string>(
        fallback_encodings.begin(), fallback_encodings.end());

    auto lower = std::string(hint_path);
    std::transform(lower.begin(), lower.end(), lower.begin(),
        [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    // 路径提示：含 big5/繁体 → 优先 Big5
    auto promote = [&candidates](const std::string& enc) {
        auto it = std::find(candidates.begin(), candidates.end(), enc);
        if (it != candidates.end() && it != candidates.begin()) {
            candidates.erase(it);
            candidates.insert(candidates.begin(), enc);
        }
    };

    if (lower.find("big5") != std::string::npos ||
        lower.find("繁体") != std::string::npos ||
        lower.find("cht") != std::string::npos ||
        lower.find("traditional") != std::string::npos) {
        promote("big5");
        promote("cp950");
        promote("big5-hkscs");
    }

    if (lower.find("gbk") != std::string::npos ||
        lower.find("gb2312") != std::string::npos ||
        lower.find("gb18030") != std::string::npos ||
        lower.find("简体") != std::string::npos ||
        lower.find("chs") != std::string::npos) {
        promote("gb18030");
        promote("gbk");
    }

    return candidates;
}

bool SubtitleParser::isUtf16Encoding(std::string_view encoding) noexcept {
    auto lower = std::string(encoding);
    std::transform(lower.begin(), lower.end(), lower.begin(),
        [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return lower == "utf-16le" || lower == "utf-16be";
}

// ──── 平台相关：编码 → 系统标识 ────

#if NP_WIN32
uint32_t SubtitleParser::encodingToCodepage(std::string_view encoding) noexcept {
    auto lower = std::string(encoding);
    std::transform(lower.begin(), lower.end(), lower.begin(),
        [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    if (lower == "gb18030" || lower == "gbk" || lower == "gb2312")  return 54936; // GB18030
    if (lower == "big5" || lower == "cp950" || lower == "big5-hkscs") return 950;
    if (lower == "shift_jis" || lower == "sjis")                    return 932;
    if (lower == "euc-kr")                                          return 949;
    if (lower == "windows-1252" || lower == "cp1252")               return 1252;
    if (lower == "iso-8859-1" || lower == "latin1")                 return 28591;
    if (lower == "utf-16le")                                        return 1200;
    if (lower == "utf-16be")                                        return 1201;
    return 0; // unknown
}
#elif NP_POSIX
std::string SubtitleParser::encodingToIconvName(std::string_view encoding) {
    auto lower = std::string(encoding);
    std::transform(lower.begin(), lower.end(), lower.begin(),
        [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    if (lower == "gb18030" || lower == "gbk" || lower == "gb2312")  return "GB18030";
    if (lower == "big5")                                            return "BIG5";
    if (lower == "cp950")                                           return "CP950";
    if (lower == "big5-hkscs")                                      return "BIG5-HKSCS";
    if (lower == "shift_jis")                                       return "SHIFT_JIS";
    if (lower == "euc-kr")                                          return "EUC-KR";
    if (lower == "windows-1252" || lower == "cp1252")               return "WINDOWS-1252";
    if (lower == "iso-8859-1" || lower == "latin1")                 return "ISO-8859-1";
    if (lower == "utf-16le")                                        return "UTF-16LE";
    if (lower == "utf-16be")                                        return "UTF-16BE";
    return {}; // unknown
}
#else
// Android: 无 iconv/Windows API，这两个函数不会被调用
// （convertToUtf8 在 Android 分支直接返回 nullopt）
uint32_t SubtitleParser::encodingToCodepage(std::string_view) noexcept { return 0; }
std::string SubtitleParser::encodingToIconvName(std::string_view) { return {}; }
#endif

} // namespace nipaplay::native
