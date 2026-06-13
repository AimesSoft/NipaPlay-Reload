#include <exception>
#include <new>
#include <cstddef>
#include <cstring>
#include <cstdlib>
#include <string>
#include <string_view>

#include "nipaplay_native/nipaplay_native.h"
#include "nipaplay_native/types.h"
#include "example_calculator.h"
#include "danmaku_layout.h"
#include "similarity_engine.h"
#include "danmaku_parser.h"
#include "subtitle_parser.h"

// ──── 辅助：NpString 内部分配（C++ 内部函数，非 extern "C"） ────
NpString np_string_alloc(std::string_view s);

// ──── 辅助：捕获异常消息到 thread-local 缓冲区 ────
// e.what() 指向的字符串在 catch 块返回后即被销毁，
// 必须拷贝到拥有独立生命周期的缓冲区中，确保 Dart 侧 FFI 读取时有效。
// 使用 thread-local 保证线程安全，且无需手动释放。
namespace {
thread_local std::string tl_last_error_msg;

const char* saveErrorMessage(const char* msg) {
    tl_last_error_msg = msg ? msg : "";
    return tl_last_error_msg.c_str();
}
} // anonymous namespace

// ──── 库级 API ────

NIPAPLAY_NATIVE_EXPORT int32_t np_get_version(void) {
    return 1;  // v0.1
}

// ──── 内存管理 ────

NIPAPLAY_NATIVE_EXPORT void np_string_free(NpString* str) {
    if (str && str->data) {
        std::free(const_cast<char*>(str->data));
        str->data = nullptr;
        str->length = 0;
    }
}

NIPAPLAY_NATIVE_EXPORT void np_free_ptr(void* ptr) {
    std::free(ptr);
}

// ──── 示例模块：ExampleCalculator ────

NIPAPLAY_NATIVE_EXPORT NpHandle np_example_create(void) {
    try {
        auto* obj = new nipaplay::native::ExampleCalculator();
        return static_cast<NpHandle>(obj);
    } catch (const std::bad_alloc&) {
        return nullptr;
    } catch (...) {
        return nullptr;
    }
}

NIPAPLAY_NATIVE_EXPORT void np_example_destroy(NpHandle handle) {
    if (handle) [[likely]] {
        auto* obj = static_cast<nipaplay::native::ExampleCalculator*>(handle);
        delete obj;
    }
}

NIPAPLAY_NATIVE_EXPORT int32_t np_example_add(NpHandle handle, int32_t a, int32_t b) {
    try {
        if (!handle) [[unlikely]] return 0;
        auto* obj = static_cast<nipaplay::native::ExampleCalculator*>(handle);
        return obj->add(a, b);
    } catch (...) {
        return 0;
    }
}

NIPAPLAY_NATIVE_EXPORT NpResult np_example_process_text(
    NpHandle handle, const char* input, NpString* output) {
    try {
        if (!handle || !input || !output) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null pointer argument"};
        }
        auto* obj = static_cast<nipaplay::native::ExampleCalculator*>(handle);
        std::string result = obj->processText(input);
        *output = np_string_alloc(result);
        if (!output->data) [[unlikely]] {
            return {NP_ERR_OOM, "failed to allocate NpString"};
        }
        return {NP_OK, nullptr};
    } catch (const std::bad_alloc&) {
        return {NP_ERR_OOM, "out of memory"};
    } catch (const std::exception& e) {
        return {NP_ERR_INTERNAL, saveErrorMessage(e.what())};
    } catch (...) {
        return {NP_ERR_INTERNAL, "unknown C++ exception"};
    }
}

// ──── 弹幕布局引擎：DanmakuLayoutEngine ────

NIPAPLAY_NATIVE_EXPORT NpHandle np_layout_create(void) {
    try {
        auto* obj = new nipaplay::native::DanmakuLayoutEngine();
        return static_cast<NpHandle>(obj);
    } catch (const std::bad_alloc&) {
        return nullptr;
    } catch (...) {
        return nullptr;
    }
}

NIPAPLAY_NATIVE_EXPORT void np_layout_destroy(NpHandle handle) {
    if (handle) [[likely]] {
        auto* obj = static_cast<nipaplay::native::DanmakuLayoutEngine*>(handle);
        delete obj;
    }
}

NIPAPLAY_NATIVE_EXPORT NpResult np_layout_configure(
    NpHandle handle,
    const NpDanmakuItem* items, int32_t item_count,
    double width, double height,
    double font_size, double display_area,
    double scroll_duration, double static_duration,
    int32_t allow_stacking,
    double base_danmaku_height,
    double base_track_height)
{
    try {
        if (!handle) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null handle"};
        }
        if (item_count > 0 && !items) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null items with count > 0"};
        }
        if (width <= 0 || height <= 0) [[unlikely]] {
            return {NP_ERR_INVALID_ARG, "width/height must be positive"};
        }

        auto* engine = static_cast<nipaplay::native::DanmakuLayoutEngine*>(handle);

        // 将 C 结构体数组转换为 C++ LayoutItem 向量
        std::vector<nipaplay::native::LayoutItem> cppItems;
        cppItems.reserve(static_cast<size_t>(item_count));
        for (int32_t i = 0; i < item_count; i++) {
            const NpDanmakuItem& src = items[i];
            cppItems.push_back({
                .time_seconds = src.time_seconds,
                .type = static_cast<nipaplay::native::DanmakuType>(src.type),
                .text_width = src.text_width,
                .font_size_multiplier = src.font_size_multiplier,
                .is_me = src.is_me != 0,
                .stack_hash = src.stack_hash,
                .track_index = -1,
                .y_position = 0.0,
                .scroll_speed = 0.0,
            });
        }

        engine->configure(
            std::move(cppItems),
            width, height,
            font_size, display_area,
            scroll_duration, static_duration,
            allow_stacking != 0,
            base_danmaku_height,
            base_track_height);

        return {NP_OK, nullptr};
    } catch (const std::bad_alloc&) {
        return {NP_ERR_OOM, "out of memory"};
    } catch (const std::exception& e) {
        return {NP_ERR_INTERNAL, saveErrorMessage(e.what())};
    } catch (...) {
        return {NP_ERR_INTERNAL, "unknown C++ exception"};
    }
}

// 编译期校验：LayoutResult 与 NpLayoutResult 字段布局一致，允许零拷贝直写
static_assert(offsetof(nipaplay::native::LayoutResult, y_position) ==
              offsetof(NpLayoutResult, y_position),
              "LayoutResult::y_position offset mismatch with NpLayoutResult");
static_assert(offsetof(nipaplay::native::LayoutResult, scroll_speed) ==
              offsetof(NpLayoutResult, scroll_speed),
              "LayoutResult::scroll_speed offset mismatch with NpLayoutResult");
static_assert(offsetof(nipaplay::native::LayoutResult, item_index) ==
              offsetof(NpLayoutResult, item_index),
              "LayoutResult::item_index offset mismatch with NpLayoutResult");
static_assert(offsetof(nipaplay::native::LayoutResult, track_index) ==
              offsetof(NpLayoutResult, track_index),
              "LayoutResult::track_index offset mismatch with NpLayoutResult");
static_assert(sizeof(nipaplay::native::LayoutResult) == sizeof(NpLayoutResult),
              "LayoutResult size mismatch with NpLayoutResult");

// 编译期校验：FrameRawOutput 与 NpFrameRawOutput 字段布局一致，允许零拷贝直写
static_assert(offsetof(nipaplay::native::FrameRawOutput, y_position) ==
              offsetof(NpFrameRawOutput, y_position),
              "FrameRawOutput::y_position offset mismatch");
static_assert(offsetof(nipaplay::native::FrameRawOutput, x) ==
              offsetof(NpFrameRawOutput, x),
              "FrameRawOutput::x offset mismatch");
static_assert(offsetof(nipaplay::native::FrameRawOutput, scroll_speed) ==
              offsetof(NpFrameRawOutput, scroll_speed),
              "FrameRawOutput::scroll_speed offset mismatch");
static_assert(offsetof(nipaplay::native::FrameRawOutput, offstage_x) ==
              offsetof(NpFrameRawOutput, offstage_x),
              "FrameRawOutput::offstage_x offset mismatch");
static_assert(offsetof(nipaplay::native::FrameRawOutput, text_width) ==
              offsetof(NpFrameRawOutput, text_width),
              "FrameRawOutput::text_width offset mismatch");
static_assert(offsetof(nipaplay::native::FrameRawOutput, item_index) ==
              offsetof(NpFrameRawOutput, item_index),
              "FrameRawOutput::item_index offset mismatch");
static_assert(offsetof(nipaplay::native::FrameRawOutput, type) ==
              offsetof(NpFrameRawOutput, type),
              "FrameRawOutput::type offset mismatch");
static_assert(sizeof(nipaplay::native::FrameRawOutput) == sizeof(NpFrameRawOutput),
              "FrameRawOutput size mismatch with NpFrameRawOutput");

NIPAPLAY_NATIVE_EXPORT NpResult np_layout_frame(
    NpHandle handle, double current_time,
    NpLayoutResult* output_items, int32_t output_capacity,
    int32_t* output_count)
{
    try {
        if (!handle) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null handle"};
        }
        if (!output_items || !output_count) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null output pointer"};
        }
        if (output_capacity <= 0) [[unlikely]] {
            *output_count = 0;
            return {NP_OK, nullptr};
        }

        auto* engine = static_cast<nipaplay::native::DanmakuLayoutEngine*>(handle);

        // LayoutResult 与 NpLayoutResult 布局完全一致（由 static_assert 保证），
        // 直接写入 Dart 预分配缓冲区，消除每帧堆分配 + 逐字段拷贝
        auto* results = reinterpret_cast<nipaplay::native::LayoutResult*>(output_items);
        const int32_t count = engine->frame(current_time, results, output_capacity);

        *output_count = count;

        return {NP_OK, nullptr};
    } catch (const std::bad_alloc&) {
        return {NP_ERR_OOM, "out of memory"};
    } catch (const std::exception& e) {
        return {NP_ERR_INTERNAL, saveErrorMessage(e.what())};
    } catch (...) {
        return {NP_ERR_INTERNAL, "unknown C++ exception"};
    }
}

NIPAPLAY_NATIVE_EXPORT NpResult np_layout_frame_raw(
    NpHandle handle, double current_time,
    NpFrameRawOutput* output_items, int32_t output_capacity,
    int32_t* output_count)
{
    try {
        if (!handle) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null handle"};
        }
        if (!output_items || !output_count) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null output pointer"};
        }
        if (output_capacity <= 0) [[unlikely]] {
            *output_count = 0;
            return {NP_OK, nullptr};
        }

        auto* engine = static_cast<nipaplay::native::DanmakuLayoutEngine*>(handle);

        // FrameRawOutput 与 NpFrameRawOutput 布局完全一致（由 static_assert 保证），
        // 直接写入 Dart 预分配缓冲区 — 零拷贝直写
        auto* results = reinterpret_cast<nipaplay::native::FrameRawOutput*>(output_items);
        const int32_t count = engine->frameRaw(current_time, results, output_capacity);

        *output_count = count;

        return {NP_OK, nullptr};
    } catch (const std::bad_alloc&) {
        return {NP_ERR_OOM, "out of memory"};
    } catch (const std::exception& e) {
        return {NP_ERR_INTERNAL, saveErrorMessage(e.what())};
    } catch (...) {
        return {NP_ERR_INTERNAL, "unknown C++ exception"};
    }
}

// ──── 弹幕相似度引擎：SimilarityEngine（有状态对象）───

NIPAPLAY_NATIVE_EXPORT NpHandle np_sim_create(void) {
    try {
        auto* obj = new nipaplay::native::SimilarityEngine();
        return static_cast<NpHandle>(obj);
    } catch (const std::bad_alloc&) {
        return nullptr;
    } catch (...) {
        return nullptr;
    }
}

NIPAPLAY_NATIVE_EXPORT void np_sim_destroy(NpHandle handle) {
    if (handle) [[likely]] {
        auto* obj = static_cast<nipaplay::native::SimilarityEngine*>(handle);
        delete obj;
    }
}

NIPAPLAY_NATIVE_EXPORT NpResult np_sim_check_batch(
    NpHandle handle, const char* items_json, const char* config_json, NpString* output)
{
    try {
        if (!handle) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null handle"};
        }
        if (!items_json || !config_json || !output) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null pointer argument"};
        }
        auto* engine = static_cast<nipaplay::native::SimilarityEngine*>(handle);
        std::string result = nipaplay::native::similarity_check_batch_json(
            *engine, items_json, config_json);
        *output = np_string_alloc(result);
        if (!output->data) [[unlikely]] {
            return {NP_ERR_OOM, "failed to allocate NpString"};
        }
        return {NP_OK, nullptr};
    } catch (const std::bad_alloc&) {
        return {NP_ERR_OOM, "out of memory"};
    } catch (const std::exception& e) {
        return {NP_ERR_INTERNAL, saveErrorMessage(e.what())};
    } catch (...) {
        return {NP_ERR_INTERNAL, "unknown C++ exception"};
    }
}

NIPAPLAY_NATIVE_EXPORT double np_sim_pair_similarity(
    const char* text_a, const char* text_b, int32_t use_pinyin)
{
    try {
        if (!text_a || !text_b) [[unlikely]] return 0.0;
        return nipaplay::native::danmaku_pair_similarity(
            text_a, text_b, use_pinyin != 0);
    } catch (...) {
        return 0.0;
    }
}

// ──── 弹幕解析模块：DanmakuParser ────

NIPAPLAY_NATIVE_EXPORT NpResult np_danmaku_parse_xml(
    const char* xml_content, int64_t content_len,
    NpString* output_json)
{
    try {
        if (!xml_content || !output_json) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null pointer argument"};
        }
        if (content_len < 0) [[unlikely]] {
            return {NP_ERR_INVALID_ARG, "content_len must be >= 0"};
        }

        std::string_view xml_view(xml_content, static_cast<size_t>(content_len));
        std::string json_result = nipaplay::DanmakuParser::parseXmlToJson(xml_view);

        *output_json = np_string_alloc(json_result);
        if (!output_json->data) [[unlikely]] {
            return {NP_ERR_OOM, "failed to allocate NpString"};
        }
        return {NP_OK, nullptr};
    } catch (const std::bad_alloc&) {
        return {NP_ERR_OOM, "out of memory"};
    } catch (const std::exception& e) {
        return {NP_ERR_INTERNAL, saveErrorMessage(e.what())};
    } catch (...) {
        return {NP_ERR_INTERNAL, "unknown C++ exception"};
    }
}

NIPAPLAY_NATIVE_EXPORT NpResult np_danmaku_parse_json(
    const char* json_content, int64_t content_len,
    NpString* output_json)
{
    try {
        if (!json_content || !output_json) [[unlikely]] {
            return {NP_ERR_NULL_PTR, "null pointer argument"};
        }
        if (content_len < 0) [[unlikely]] {
            return {NP_ERR_INVALID_ARG, "content_len must be >= 0"};
        }

        std::string_view json_view(json_content, static_cast<size_t>(content_len));
        std::string json_result = nipaplay::DanmakuParser::parseJsonToStandardized(json_view);

        *output_json = np_string_alloc(json_result);
        if (!output_json->data) [[unlikely]] {
            return {NP_ERR_OOM, "failed to allocate NpString"};
        }
        return {NP_OK, nullptr};
    } catch (const std::bad_alloc&) {
        return {NP_ERR_OOM, "out of memory"};
    } catch (const std::exception& e) {
        return {NP_ERR_INTERNAL, saveErrorMessage(e.what())};
    } catch (...) {
        return {NP_ERR_INTERNAL, "unknown C++ exception"};
    }
}

// ──── 字幕解析模块：SubtitleParser ────

// 辅助：为 NpSubtitleParseResult 分配独立的错误消息
// 使用 strdup 确保生命周期独立于 thread-local 缓冲区
// 返回的指针需由 np_subtitle_free_result 释放
static const char* allocErrorMessage(const char* msg) {
    if (!msg) return nullptr;
    // MSVC 报 POSIX 弃用警告，使用 _strdup 替代
#if defined(_MSC_VER)
    auto* copy = _strdup(msg);
#else
    auto* copy = strdup(msg);
#endif
    return copy ? copy : "allocation failed";
}

NIPAPLAY_NATIVE_EXPORT NpSubtitleParseResult* np_subtitle_parse_bytes(
    const uint8_t* data, int32_t len, const char* hint_path)
{
    // 分配结果结构（零初始化）
    auto* result = static_cast<NpSubtitleParseResult*>(std::calloc(1, sizeof(NpSubtitleParseResult)));
    if (!result) [[unlikely]] {
        return nullptr;
    }

    try {
        if (!data || len <= 0) [[unlikely]] {
            result->code = NP_ERR_INVALID_ARG;
            result->error_message = allocErrorMessage("invalid data/len");
            result->format_code = -1;
            return result;
        }

        // 调用 C++ 解析器
        auto hint_sv = hint_path ? std::string_view(hint_path) : std::string_view{};
        auto output = nipaplay::native::SubtitleParser::parseBytes(data, len, hint_sv);

        // 填充 detected_encoding
        result->detected_encoding = np_string_alloc(output.detected_encoding);
        if (!result->detected_encoding.data) [[unlikely]] {
            result->code = NP_ERR_OOM;
            result->error_message = allocErrorMessage("failed to allocate encoding string");
            return result;
        }

        // 填充 format_code
        result->format_code = static_cast<int32_t>(output.format);

        // 填充 entries 数组
        const auto count = static_cast<int32_t>(output.entries.size());
        if (count > 0) {
            auto* entries = static_cast<NpSubtitleEntry*>(
                std::calloc(static_cast<size_t>(count), sizeof(NpSubtitleEntry)));
            if (!entries) [[unlikely]] {
                // 已分配的 detected_encoding 需释放
                np_string_free(&result->detected_encoding);
                result->code = NP_ERR_OOM;
                result->error_message = allocErrorMessage("failed to allocate entries array");
                return result;
            }

            for (int32_t i = 0; i < count; ++i) {
                const auto& src = output.entries[static_cast<size_t>(i)];
                auto& dst = entries[i];

                dst.start_time_ms = src.start_time_ms;
                dst.end_time_ms   = src.end_time_ms;

                dst.content = np_string_alloc(src.content);
                if (!dst.content.data) [[unlikely]] goto oom_cleanup;

                dst.style = np_string_alloc(src.style);
                if (!dst.style.data) [[unlikely]] goto oom_cleanup;

                dst.name = np_string_alloc(src.name);
                if (!dst.name.data) [[unlikely]] goto oom_cleanup;
            }

            result->entries = entries;
            result->entry_count = count;
        } else {
            result->entries = nullptr;
            result->entry_count = 0;
        }

        result->code = NP_OK;
        result->error_message = nullptr;
        return result;

    oom_cleanup:
        // 部分分配失败：回滚已分配的 NpString
        if (result->entries) {
            for (int32_t i = 0; i < count; ++i) {
                np_string_free(&result->entries[i].content);
                np_string_free(&result->entries[i].style);
                np_string_free(&result->entries[i].name);
            }
            std::free(result->entries);
            result->entries = nullptr;
        }
        np_string_free(&result->detected_encoding);
        result->code = NP_ERR_OOM;
        result->error_message = allocErrorMessage("out of memory during entry allocation");
        return result;

    } catch (const std::bad_alloc&) {
        result->code = NP_ERR_OOM;
        result->error_message = allocErrorMessage("out of memory");
        return result;
    } catch (const std::exception& e) {
        result->code = NP_ERR_INTERNAL;
        result->error_message = allocErrorMessage(e.what());
        return result;
    } catch (...) {
        result->code = NP_ERR_INTERNAL;
        result->error_message = allocErrorMessage("unknown C++ exception");
        return result;
    }
}

NIPAPLAY_NATIVE_EXPORT void np_subtitle_free_result(
    NpSubtitleParseResult* result)
{
    if (!result) [[unlikely]] return;

    // 释放 entries 数组中所有 NpString
    if (result->entries) {
        for (int32_t i = 0; i < result->entry_count; ++i) {
            np_string_free(&result->entries[i].content);
            np_string_free(&result->entries[i].style);
            np_string_free(&result->entries[i].name);
        }
        std::free(result->entries);
        result->entries = nullptr;
    }

    // 释放 detected_encoding
    np_string_free(&result->detected_encoding);

    // 释放 error_message（由 allocErrorMessage/strdup 分配）
    if (result->error_message) {
        std::free(const_cast<char*>(result->error_message));
        result->error_message = nullptr;
    }

    // 释放 result 本身
    std::free(result);
}
