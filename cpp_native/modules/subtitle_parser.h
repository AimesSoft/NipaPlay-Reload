#pragma once
/// @file subtitle_parser.h
/// @brief 字幕解析器 — 支持 ASS/SRT/SubViewer/MicroDVD 四种格式
///        内建编码检测（BOM + UTF-8 验证 + 回退列表）
///        平台相关编码转换（Windows: MultiByteToWideChar; POSIX: iconv）
///
/// 现代 C++ 特性使用：
///   C++20 — constexpr 函数、[[likely]]/[[unlikely]]、enum class、
///           std::string_view 的 constexpr find/substr
///   C++17 — std::string_view、std::optional、std::vector::reserve、
///           结构化绑定、if constexpr、inline 变量

#include <string>
#include <string_view>
#include <vector>
#include <optional>
#include <cstdint>

namespace nipaplay::native {

// ──── 字幕格式枚举 ────
enum class SubtitleFormat : int32_t {
    ASS       = 0,
    SRT       = 1,
    SubViewer = 2,
    MicroDVD  = 3,
    Unknown   = -1
};

// ──── 字幕条目（与 Dart SubtitleEntry 对应）────
struct SubtitleEntry {
    int32_t start_time_ms = 0;
    int32_t end_time_ms   = 0;
    std::string content;          ///< 字幕文本（已清理 ASS 标记）
    std::string style{"Default"}; ///< ASS 样式名
    std::string layer{"0"};       ///< ASS 图层
    std::string name;             ///< ASS 角色名
    std::string effect;           ///< ASS 特效
};

// ──── 解析输出 ────
struct SubtitleParseOutput {
    std::vector<SubtitleEntry> entries;
    SubtitleFormat format = SubtitleFormat::Unknown;
    std::string detected_encoding{"utf-8"};
};

// ──── 字幕解析器 ────
class SubtitleParser {
public:
    /// 主入口：解析字节数据，自动检测编码和格式
    /// @param data 原始字节
    /// @param len  字节长度
    /// @param hint_path 可选文件路径，用于编码/格式提示（如含 "big5" 优先尝试 Big5）
    static SubtitleParseOutput parseBytes(
        const uint8_t* data, int32_t len,
        std::string_view hint_path = {});

    /// 格式专用解析器（输入已为 UTF-8 文本）
    static std::vector<SubtitleEntry> parseAss(std::string_view content);
    static std::vector<SubtitleEntry> parseSrt(std::string_view content);
    static std::vector<SubtitleEntry> parseSubViewer(std::string_view content);
    static std::vector<SubtitleEntry> parseMicrodvd(
        std::string_view content, double default_fps = 23.976);

    /// 格式检测（内容 + 文件路径提示）
    static SubtitleFormat detectFormat(
        std::string_view content, std::string_view hint_path);

private:
    // ──── constexpr 时间解析（C++20 允许 string_view constexpr 操作）────
    static constexpr int32_t parseTimeToMs(std::string_view time_str) noexcept {
        const auto c1 = time_str.find(':');
        if (c1 == std::string_view::npos) [[unlikely]] return 0;
        const auto c2 = time_str.find(':', c1 + 1);
        if (c2 == std::string_view::npos) [[unlikely]] return 0;

        const auto h_str = time_str.substr(0, c1);
        const auto m_str = time_str.substr(c1 + 1, c2 - c1 - 1);
        const auto s_part = time_str.substr(c2 + 1);

        const int32_t h = parseUint(h_str);
        const int32_t m = parseUint(m_str);

        const auto dot = s_part.find_first_of(".,");
        int32_t sec = 0, sub = 0;
        bool is_cs = false; // centiseconds?

        if (dot != std::string_view::npos) {
            sec = parseUint(s_part.substr(0, dot));
            const auto frac = s_part.substr(dot + 1);
            is_cs = frac.length() <= 2;  // ≤2 位 → 厘秒; >2 位 → 毫秒
            sub = parseUint(frac);
        } else {
            sec = parseUint(s_part);
        }
        if (is_cs) sub *= 10; // 厘秒 → 毫秒

        return (h * 3600 + m * 60 + sec) * 1000 + sub;
    }

    /// constexpr 无符号整数解析
    static constexpr int32_t parseUint(std::string_view s) noexcept {
        int32_t r = 0;
        for (char c : s) {
            if (c < '0' || c > '9') [[unlikely]] break;
            r = r * 10 + (c - '0');
        }
        return r;
    }

    // ──── 编码检测 ────
    static std::optional<std::string> detectBomEncoding(
        const uint8_t* data, int32_t len);
    static bool isValidUtf8(const uint8_t* data, int32_t len) noexcept;

    /// 综合编码检测：BOM → UTF-8 验证 → 回退列表 + 路径提示
    static std::optional<std::string> detectEncoding(
        const uint8_t* data, int32_t len, std::string_view hint_path);

    // ──── 编码转换 ────
    /// 将字节从指定编码转为 UTF-8；strip_bom 跳过 BOM 前缀
    static std::optional<std::string> convertToUtf8(
        const uint8_t* data, int32_t len,
        std::string_view encoding, bool strip_bom = false);

    /// UTF-16 解码（手动，跨平台）
    static std::string decodeUtf16(
        const uint8_t* data, int32_t len, bool little_endian);

    // ──── 文本质量评估 ────
    static bool looksLikeText(std::string_view text);
    static bool looksBinary(const uint8_t* data, int32_t len) noexcept;
    static bool looksLikeUtf16(const uint8_t* data, int32_t len) noexcept;
    static double scoreDecodedText(
        std::string_view text, std::string_view hint_path,
        std::string_view encoding, SubtitleFormat format);
    static double scoreEncodingHint(
        std::string_view hint_path, std::string_view encoding);

    // ──── CJK 字符分类 (constexpr) ────
    static constexpr bool isCjkCodePoint(char32_t c) noexcept {
        return (c >= 0x4E00 && c <= 0x9FFF) ||  // CJK Unified
               (c >= 0x3400 && c <= 0x4DBF) ||  // CJK Extension A
               (c >= 0xF900 && c <= 0xFAFF) ||  // CJK Compatibility
               (c >= 0x3040 && c <= 0x30FF) ||  // Hiragana+Katakana
               (c >= 0xAC00 && c <= 0xD7AF);    // Hangul Syllables
    }
    static constexpr bool isCjkPunctuation(char32_t c) noexcept {
        return (c >= 0x3000 && c <= 0x303F) ||  // CJK Symbols
               (c >= 0xFF00 && c <= 0xFFEF) ||  // Halfwidth/Fullwidth
               c == 0x201C || c == 0x201D ||     // " "
               c == 0x2018 || c == 0x2019;       // ' '
    }

    // ──── ASS 辅助 ────
    static std::string cleanAssText(std::string_view text);
    static void splitDialogueLine(
        std::string_view line, std::vector<std::string_view>& out);

    // ──── 编码名处理 ────
    static std::optional<std::string> normalizeEncodingName(std::string_view raw);
    static std::vector<std::string> buildEncodingCandidates(std::string_view hint_path);
    static bool isUtf16Encoding(std::string_view encoding) noexcept;

    // ──── 平台相关：编码名 → 系统编码标识 ────
    #if defined(_WIN32)
    static uint32_t encodingToCodepage(std::string_view encoding) noexcept;
    #elif defined(__ANDROID__)
    // Android: 无 iconv，提供空实现（convertToUtf8 Android 分支直接返回 nullopt）
    static uint32_t encodingToCodepage(std::string_view encoding) noexcept;
    static std::string encodingToIconvName(std::string_view encoding);
    #else
    static std::string encodingToIconvName(std::string_view encoding);
    #endif
};

} // namespace nipaplay::native
