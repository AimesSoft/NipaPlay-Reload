#include "similarity_engine.h"
#include "nipaplay_native/nipaplay_native.h"

#include <cmath>
#include <cstdio>
#include <new>
#include <stdexcept>
#include <functional>

// ══════════════════════════════════════════════
// ──── SimilarityEngine 构造函数 ────
// ══════════════════════════════════════════════

namespace nipaplay::native {

SimilarityEngine::SimilarityEngine()
    : ed_a_(std::make_unique<short[]>(SIM_MAX_HASH_VAL))
    , ed_b_(std::make_unique<short[]>(SIM_MAX_HASH_VAL))
{
    std::memset(ed_a_.get(), 0, SIM_MAX_HASH_VAL * sizeof(short));
    std::memset(ed_b_.get(), 0, SIM_MAX_HASH_VAL * sizeof(short));
}

// ══════════════════════════════════════════════
// ──── UTF-8 → UTF-16 转换 ────
// ══════════════════════════════════════════════

static std::vector<sim_ushort> utf8_to_utf16(const std::string& text) {
    std::vector<sim_ushort> result;
    result.reserve(text.size());
    const uint8_t* s = reinterpret_cast<const uint8_t*>(text.data());
    const uint8_t* end = s + text.size();

    while (s < end) {
        uint32_t cp = 0;
        int bytes = 0;
        if ((*s & 0x80) == 0) {
            cp = *s; bytes = 1;
        } else if ((*s & 0xE0) == 0xC0) {
            cp = *s & 0x1F; bytes = 2;
        } else if ((*s & 0xF0) == 0xE0) {
            cp = *s & 0x0F; bytes = 3;
        } else if ((*s & 0xF8) == 0xF0) {
            cp = *s & 0x07; bytes = 4;
        } else {
            s++; continue; // invalid byte, skip
        }

        if (s + bytes > end) break;
        for (int i = 1; i < bytes; i++) {
            if ((s[i] & 0xC0) != 0x80) { bytes = 0; break; }
            cp = (cp << 6) | (s[i] & 0x3F);
        }
        if (bytes == 0) { s++; continue; }
        s += bytes;

        // Encode code point as UTF-16
        if (cp <= 0xFFFF) {
            result.push_back(static_cast<sim_ushort>(cp));
        } else {
            cp -= 0x10000;
            result.push_back(static_cast<sim_ushort>(0xD800 + (cp >> 10)));
            result.push_back(static_cast<sim_ushort>(0xDC00 + (cp & 0x3FF)));
        }
    }
    return result;
}

// ──── compute_score ────
// 从 Rust similarity.rs 的 compute_score 移植
static double compute_score(sim_uint reason_code, int dist, size_t text_len) {
    switch (reason_code) {
    case 0: return 1.0;                                              // identical
    case 1: case 2:                                                  // edit/pinyin distance
        if (text_len == 0) return 0.0;
        return 1.0 - (dist / (std::max(static_cast<double>(text_len) * 2.0, 1.0)));
    case 3: return dist / 100.0;                                     // cosine similarity
    default: return 0.0;
    }
}

// ──── 饱和减法 ────
static sim_uint saturating_sub(sim_uint a, sim_uint b) {
    return a >= b ? a - b : 0;
}

// ──── update_groups ────
// 从 Rust similarity.rs 的 update_groups 移植
static void update_groups(
    std::unordered_map<int, int>& group_map,
    std::vector<std::vector<int>>& groups,
    int a, int b)
{
    auto it_a = group_map.find(a);
    auto it_b = group_map.find(b);
    bool has_a = it_a != group_map.end();
    bool has_b = it_b != group_map.end();

    if (has_a && has_b && it_a->second == it_b->second) {
        // Same group
    } else if (has_a && has_b) {
        int ra = it_a->second;
        int rb = it_b->second;
        auto merged = std::move(groups[static_cast<size_t>(ra)]);
        auto other = std::move(groups[static_cast<size_t>(rb)]);
        merged.insert(merged.end(), other.begin(), other.end());
        for (int idx : merged) {
            group_map[idx] = ra;
        }
        groups[static_cast<size_t>(ra)] = std::move(merged);
        groups[static_cast<size_t>(rb)].clear(); // leave empty slot
    } else if (has_a) {
        int ra = it_a->second;
        groups[static_cast<size_t>(ra)].push_back(b);
        group_map[b] = ra;
    } else if (has_b) {
        int rb = it_b->second;
        groups[static_cast<size_t>(rb)].push_back(a);
        group_map[a] = rb;
    } else {
        int group_idx = static_cast<int>(groups.size());
        groups.push_back({b, a});
        group_map[a] = group_idx;
        group_map[b] = group_idx;
    }
}

// ══════════════════════════════════════════════
// ──── 批量查重：高级 API ────
// ══════════════════════════════════════════════

SimResult danmaku_similarity_check(
    const std::vector<DanmakuSimItem>& items,
    const SimConfig& config)
{
    SimResult result;

    // NOTE: O(n²) comparison loop — no upper bound on items size.
    // In typical danmaku scenarios batches are small (<1000), but if
    // very large batches are ever passed, consider adding a cap or
    // switching to a streaming approach to avoid pathological performance.

    auto engine = std::make_unique<SimilarityEngine>();
    if (!engine) return result;

    constexpr size_t MAX_STRING_LEN = 16005;
    auto str_buf = std::vector<sim_ushort>(MAX_STRING_LEN + 4, 0);

    engine->begin_chunk(str_buf.data(),
                        config.max_dist, config.max_cosine,
                        config.use_pinyin, config.cross_mode);

    std::vector<SimPair>& pairs = result.pairs;
    std::unordered_map<int, int> group_map;
    std::vector<std::vector<int>>& groups = result.groups;
    double time_window = config.time_window;

    sim_uint c_nearby_count = 0;
    std::vector<int> engine_to_orig;

    for (size_t i = 0; i < items.size(); i++) {
        const auto& item = items[i];

        // UTF-8 → UTF-16
        auto utf16 = utf8_to_utf16(item.text);
        size_t copy_len = std::min(utf16.size(), MAX_STRING_LEN - 1);
        std::copy(utf16.begin(), utf16.begin() + static_cast<std::ptrdiff_t>(copy_len), str_buf.begin());
        str_buf[copy_len] = 0; // null terminator

        // 计算 index_l
        sim_uint index_l = c_nearby_count;
        if (time_window > 0.0 && !engine_to_orig.empty()) {
            for (size_t eng_idx = 0; eng_idx < engine_to_orig.size(); eng_idx++) {
                int orig_idx = engine_to_orig[eng_idx];
                if (orig_idx >= 0 && static_cast<size_t>(orig_idx) < items.size()
                    && item.time_seconds - items[static_cast<size_t>(orig_idx)].time_seconds <= time_window)
                {
                    index_l = static_cast<sim_uint>(eng_idx);
                    break;
                }
            }
        }

        sim_uint ret = engine->check_similar(static_cast<sim_uint>(item.mode), index_l);

        if (ret != 0) {
            sim_uint reason_code = ret >> 30;
            int dist = static_cast<int>((ret >> 19) & ((1 << 11) - 1));
            int idx_diff = static_cast<int>(ret & ((1 << 19) - 1));

            sim_uint current_engine_size = c_nearby_count;
            sim_uint matched_engine_idx = saturating_sub(current_engine_size, static_cast<sim_uint>(idx_diff));

            int target_index = (matched_engine_idx < engine_to_orig.size())
                ? engine_to_orig[matched_engine_idx]
                : static_cast<int>(i) - idx_diff;

            // 时间窗口安全校验
            if (target_index < 0
                || static_cast<size_t>(target_index) >= items.size()
                || (time_window > 0.0
                    && item.time_seconds - items[static_cast<size_t>(target_index)].time_seconds > time_window))
            {
                // 窗口外匹配拒绝 → force_insert
                engine->force_insert(static_cast<sim_uint>(item.mode));
                c_nearby_count++;
                engine_to_orig.push_back(static_cast<int>(i));
                continue;
            }

            const char* reason_str = "";
            switch (reason_code) {
            case 0: reason_str = "identical"; break;
            case 1: reason_str = "edit_distance"; break;
            case 2: reason_str = "pinyin_distance"; break;
            case 3: reason_str = "cosine"; break;
            default: reason_str = "unknown"; break;
            }

            double score = compute_score(reason_code, dist, item.text.size());

            pairs.push_back(SimPair{
                .source_index = static_cast<int>(i),
                .target_index = target_index,
                .reason = reason_str,
                .distance = dist,
                .score = score,
            });

            update_groups(group_map, groups, static_cast<int>(i), target_index);
        } else {
            // 未匹配，被加入 nearby_danmu_ 末尾
            c_nearby_count++;
            engine_to_orig.push_back(static_cast<int>(i));
        }
    }

    engine->reset();
    return result;
}

// ══════════════════════════════════════════════
// ──── 单对相似度 ────
// ══════════════════════════════════════════════

double danmaku_pair_similarity(
    const std::string& text_a,
    const std::string& text_b,
    bool use_pinyin)
{
    auto engine = std::make_unique<SimilarityEngine>();
    if (!engine) return 0.0;

    constexpr size_t MAX_STRING_LEN = 16005;
    auto str_buf = std::vector<sim_ushort>(MAX_STRING_LEN + 4, 0);

    engine->begin_chunk(str_buf.data(),
                        999,   // 不设编辑距离上限
                        101,   // 禁用余弦检测 (>100 时 max_cosine<=100 判断为 false)
                        use_pinyin,
                        true); // 单对比较忽略 mode

    // 送入第一条
    auto utf16_0 = utf8_to_utf16(text_a);
    size_t copy_len = std::min(utf16_0.size(), MAX_STRING_LEN - 1);
    std::copy(utf16_0.begin(), utf16_0.begin() + static_cast<std::ptrdiff_t>(copy_len), str_buf.begin());
    str_buf[copy_len] = 0;
    engine->check_similar(0, 0);

    // 送入第二条并获取结果
    auto utf16_1 = utf8_to_utf16(text_b);
    copy_len = std::min(utf16_1.size(), MAX_STRING_LEN - 1);
    std::copy(utf16_1.begin(), utf16_1.begin() + static_cast<std::ptrdiff_t>(copy_len), str_buf.begin());
    str_buf[copy_len] = 0;
    sim_uint ret = engine->check_similar(0, 0);

    if (ret == 0) return 0.0;

    sim_uint reason_code = ret >> 30;
    int dist = static_cast<int>((ret >> 19) & ((1 << 11) - 1));
    return compute_score(reason_code, dist, text_b.size());
}

// ══════════════════════════════════════════════
// ──── JSON 便捷接口 ────
// ══════════════════════════════════════════════

// 最小化 JSON 解析器 — 仅支持 similarity 所需的结构
// 不依赖第三方库（如 rapidjson/nlohmann），保持 cpp_native 零外部依赖。

namespace json_util {

// 跳过空白
static const char* skip_ws(const char* p) {
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    return p;
}

// 解析 JSON string，返回内容（不含引号），推进指针
static std::string parse_string(const char*& p) {
    p = skip_ws(p);
    if (*p != '"') { p++; return ""; }
    p++; // skip opening "
    std::string result;
    while (*p && *p != '"') {
        if (*p == '\\' && *(p+1)) {
            p++;
            switch (*p) {
            case '"': result += '"'; break;
            case '\\': result += '\\'; break;
            case 'n': result += '\n'; break;
            case 't': result += '\t'; break;
            case 'r': result += '\r'; break;
            case 'u': {
                // Unicode escape: \uXXXX (with UTF-16 surrogate pair support)
                // Handles \uD83D\uDE00 style emoji escapes produced by some
                // JSON serializers. Dart's json.encode uses proper UTF-8,
                // so this path is rarely hit but included for correctness.
                auto parse_hex4 = [](const char* s) -> unsigned int {
                    unsigned int cp = 0;
                    for (int i = 0; i < 4; i++) {
                        char c = s[i];
                        cp <<= 4;
                        if (c >= '0' && c <= '9') cp |= static_cast<unsigned int>(c - '0');
                        else if (c >= 'a' && c <= 'f') cp |= static_cast<unsigned int>(c - 'a' + 10);
                        else if (c >= 'A' && c <= 'F') cp |= static_cast<unsigned int>(c - 'A' + 10);
                    }
                    return cp;
                };
                if (p[1] && p[2] && p[3] && p[4]) {
                    unsigned int cp = parse_hex4(p + 1);
                    p += 4;
                    // UTF-16 surrogate pair handling
                    if (cp >= 0xD800 && cp <= 0xDBFF) {
                        // High surrogate — look for \uXXXX low surrogate
                        if (p[1] == '\\' && p[2] == 'u' &&
                            p[3] && p[4] && p[5] && p[6]) {
                            unsigned int low = parse_hex4(p + 3);
                            if (low >= 0xDC00 && low <= 0xDFFF) {
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                                p += 6; // consume \uXXXX of low surrogate
                            }
                        }
                    }
                    // UTF-8 encode
                    if (cp <= 0x7F) {
                        result += static_cast<char>(cp);
                    } else if (cp <= 0x7FF) {
                        result += static_cast<char>(0xC0 | (cp >> 6));
                        result += static_cast<char>(0x80 | (cp & 0x3F));
                    } else if (cp <= 0xFFFF) {
                        result += static_cast<char>(0xE0 | (cp >> 12));
                        result += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                        result += static_cast<char>(0x80 | (cp & 0x3F));
                    } else if (cp <= 0x10FFFF) {
                        result += static_cast<char>(0xF0 | (cp >> 18));
                        result += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
                        result += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                        result += static_cast<char>(0x80 | (cp & 0x3F));
                    }
                }
                break;
            }
            default: result += *p; break;
            }
        } else {
            result += *p;
        }
        p++;
    }
    if (*p == '"') p++; // skip closing "
    return result;
}

// 解析 JSON number (int or double)
static double parse_number(const char*& p) {
    p = skip_ws(p);
    char* end;
    double val = strtod(p, &end);
    p = end;
    return val;
}

// 解析 JSON bool
static bool parse_bool(const char*& p) {
    p = skip_ws(p);
    if (strncmp(p, "true", 4) == 0) { p += 4; return true; }
    if (strncmp(p, "false", 5) == 0) { p += 5; return false; }
    p++;
    return false;
}

// 跳过一个 JSON value（用于跳过不需要的字段）
static void skip_value(const char*& p) {
    p = skip_ws(p);
    if (*p == '"') { parse_string(p); }
    else if (*p == '{') {
        p++; // skip {
        while (*p && *p != '}') {
            p = skip_ws(p);
            if (*p == '}') break;
            parse_string(p); // key
            p = skip_ws(p);
            if (*p == ':') p++;
            skip_value(p);
            p = skip_ws(p);
            if (*p == ',') p++;
        }
        if (*p == '}') p++;
    }
    else if (*p == '[') {
        p++; // skip [
        while (*p && *p != ']') {
            p = skip_ws(p);
            if (*p == ']') break;
            skip_value(p);
            p = skip_ws(p);
            if (*p == ',') p++;
        }
        if (*p == ']') p++;
    }
    else if (*p == 't' || *p == 'f') { parse_bool(p); }
    else if (*p == 'n') { p += 4; } // null
    else { parse_number(p); } // number
}

// JSON 字符串转义
static std::string escape_json(const std::string& s) {
    std::string result;
    result.reserve(s.size() + 4);
    for (char c : s) {
        switch (c) {
        case '"': result += "\\\""; break;
        case '\\': result += "\\\\"; break;
        case '\n': result += "\\n"; break;
        case '\r': result += "\\r"; break;
        case '\t': result += "\\t"; break;
        default:
            if (static_cast<unsigned char>(c) < 0x20) {
                char buf[8];
                snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned char>(c));
                result += buf;
            } else {
                result += c;
            }
            break;
        }
    }
    return result;
}

} // namespace json_util

// ──── 解析 DanmakuSimItem 数组 ────
static std::vector<DanmakuSimItem> parse_items_json(const std::string& json) {
    std::vector<DanmakuSimItem> items;
    const char* p = json.c_str();
    p = json_util::skip_ws(p);
    if (*p != '[') return items;
    p++; // skip [

    while (*p && *p != ']') {
        p = json_util::skip_ws(p);
        if (*p == ']') break;
        if (*p == ',') { p++; continue; }
        if (*p != '{') { json_util::skip_value(p); continue; }

        DanmakuSimItem item;
        p++; // skip {
        while (*p && *p != '}') {
            p = json_util::skip_ws(p);
            if (*p == '}') break;
            std::string key = json_util::parse_string(p);
            p = json_util::skip_ws(p);
            if (*p == ':') p++;

            if (key == "text") {
                item.text = json_util::parse_string(p);
            } else if (key == "mode") {
                item.mode = static_cast<int>(json_util::parse_number(p));
            } else if (key == "time_seconds") {
                item.time_seconds = json_util::parse_number(p);
            } else {
                json_util::skip_value(p);
            }

            p = json_util::skip_ws(p);
            if (*p == ',') p++;
        }
        if (*p == '}') p++;
        items.push_back(std::move(item));

        p = json_util::skip_ws(p);
        if (*p == ',') p++;
    }
    return items;
}

// ──── 解析 SimConfig ────
static SimConfig parse_config_json(const std::string& json) {
    SimConfig config;
    const char* p = json.c_str();
    p = json_util::skip_ws(p);
    if (*p != '{') return config;
    p++; // skip {

    while (*p && *p != '}') {
        p = json_util::skip_ws(p);
        if (*p == '}') break;
        std::string key = json_util::parse_string(p);
        p = json_util::skip_ws(p);
        if (*p == ':') p++;

        if (key == "max_dist") {
            config.max_dist = static_cast<int>(json_util::parse_number(p));
        } else if (key == "max_cosine") {
            config.max_cosine = static_cast<int>(json_util::parse_number(p));
        } else if (key == "use_pinyin") {
            config.use_pinyin = json_util::parse_bool(p);
        } else if (key == "cross_mode") {
            config.cross_mode = json_util::parse_bool(p);
        } else if (key == "time_window") {
            config.time_window = json_util::parse_number(p);
        } else {
            json_util::skip_value(p);
        }

        p = json_util::skip_ws(p);
        if (*p == ',') p++;
    }
    return config;
}

// ──── SimResult → JSON ────
static std::string result_to_json(const SimResult& result) {
    std::string json;
    json.reserve(256);
    json += "{\"pairs\":[";

    for (size_t i = 0; i < result.pairs.size(); i++) {
        const auto& p = result.pairs[i];
        if (i > 0) json += ",";
        char buf[128];
        snprintf(buf, sizeof(buf),
            "{\"source_index\":%d,\"target_index\":%d,\"distance\":%d,\"score\":%.6f",
            p.source_index, p.target_index, p.distance, p.score);
        json += buf;
        json += ",\"reason\":\"";
        json += json_util::escape_json(p.reason);
        json += "\"}";
    }

    json += "],\"groups\":[";
    bool first_group = true;
    for (size_t i = 0; i < result.groups.size(); i++) {
        const auto& g = result.groups[i];
        if (g.empty()) continue;
        if (!first_group) json += ",";
        first_group = false;
        json += "[";
        for (size_t j = 0; j < g.size(); j++) {
            if (j > 0) json += ",";
            json += std::to_string(g[j]);
        }
        json += "]";
    }
    json += "]}";
    return json;
}

std::string similarity_check_batch_json(
    const std::string& items_json,
    const std::string& config_json)
{
    try {
        auto items = parse_items_json(items_json);
        auto config = parse_config_json(config_json);

#ifndef NDEBUG
        // 诊断：输出解析后的 items 数量和配置
        fprintf(stderr, "[SIM-CPP] parse_items_json: json_len=%zu items=%zu\n",
                items_json.size(), items.size());
        if (!items.empty()) {
            fprintf(stderr, "[SIM-CPP] first_item: text='%s' mode=%d time=%.1f\n",
                    items[0].text.substr(0, 30).c_str(), items[0].mode, items[0].time_seconds);
        }
        fprintf(stderr, "[SIM-CPP] config: max_dist=%d max_cosine=%d use_pinyin=%d cross_mode=%d time_window=%.1f\n",
                config.max_dist, config.max_cosine, config.use_pinyin, config.cross_mode, config.time_window);
#endif

        auto result = danmaku_similarity_check(items, config);

#ifndef NDEBUG
        fprintf(stderr, "[SIM-CPP] result: pairs=%zu groups=%zu\n",
                result.pairs.size(), result.groups.size());
#endif

        return result_to_json(result);
    } catch (const std::exception& e) {
        fprintf(stderr, "[SIM-CPP] EXCEPTION in similarity_check_batch_json: %s\n", e.what());
        return "{}";
    } catch (...) {
        fprintf(stderr, "[SIM-CPP] UNKNOWN EXCEPTION in similarity_check_batch_json\n");
        return "{}";
    }
}

} // namespace nipaplay::native
