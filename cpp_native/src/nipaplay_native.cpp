#include <exception>
#include <new>
#include <string>

#include "nipaplay_native/nipaplay_native.h"
#include "nipaplay_native/types.h"
#include "example_calculator.h"
#include "danmaku_layout.h"
#include "similarity_engine.h"

// ──── 辅助：NpString 内部分配（C++ 内部函数，非 extern "C"） ────
NpString np_string_alloc(const std::string& s);

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
    if (handle) {
        auto* obj = static_cast<nipaplay::native::ExampleCalculator*>(handle);
        delete obj;
    }
}

NIPAPLAY_NATIVE_EXPORT int32_t np_example_add(NpHandle handle, int32_t a, int32_t b) {
    try {
        if (!handle) return 0;
        auto* obj = static_cast<nipaplay::native::ExampleCalculator*>(handle);
        return obj->add(a, b);
    } catch (...) {
        return 0;
    }
}

NIPAPLAY_NATIVE_EXPORT NpResult np_example_process_text(
    NpHandle handle, const char* input, NpString* output) {
    try {
        if (!handle || !input || !output) {
            return {NP_ERR_NULL_PTR, "null pointer argument"};
        }
        auto* obj = static_cast<nipaplay::native::ExampleCalculator*>(handle);
        std::string result = obj->processText(std::string(input));
        *output = np_string_alloc(result);
        if (!output->data) {
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
    if (handle) {
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
        if (!handle) {
            return {NP_ERR_NULL_PTR, "null handle"};
        }
        if (item_count > 0 && !items) {
            return {NP_ERR_NULL_PTR, "null items with count > 0"};
        }
        if (width <= 0 || height <= 0) {
            return {NP_ERR_INVALID_ARG, "width/height must be positive"};
        }

        auto* engine = static_cast<nipaplay::native::DanmakuLayoutEngine*>(handle);

        // 将 C 结构体数组转换为 C++ LayoutItem 向量
        std::vector<nipaplay::native::LayoutItem> cppItems;
        cppItems.reserve(item_count);
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

NIPAPLAY_NATIVE_EXPORT NpResult np_layout_frame(
    NpHandle handle, double current_time,
    NpLayoutResult* output_items, int32_t output_capacity,
    int32_t* output_count)
{
    try {
        if (!handle) {
            return {NP_ERR_NULL_PTR, "null handle"};
        }
        if (!output_items || !output_count) {
            return {NP_ERR_NULL_PTR, "null output pointer"};
        }
        if (output_capacity <= 0) {
            *output_count = 0;
            return {NP_OK, nullptr};
        }

        auto* engine = static_cast<nipaplay::native::DanmakuLayoutEngine*>(handle);

        // 使用 C++ 内部 LayoutResult 中间缓冲区（字段顺序与 NpLayoutResult 不同）
        std::vector<nipaplay::native::LayoutResult> cppResults(output_capacity);
        const int32_t count = engine->frame(current_time, cppResults.data(), output_capacity);

        // 转换：LayoutResult → NpLayoutResult（字段顺序不同，必须逐个映射）
        for (int32_t i = 0; i < count; i++) {
            output_items[i].y_position   = cppResults[i].y_position;
            output_items[i].scroll_speed = cppResults[i].scroll_speed;
            output_items[i].item_index   = cppResults[i].item_index;
            output_items[i].track_index = cppResults[i].track_index;
        }
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

// ──── 弹幕相似度引擎：SimilarityEngine ────

NIPAPLAY_NATIVE_EXPORT NpResult np_sim_check_batch(
    const char* items_json, const char* config_json, NpString* output)
{
    try {
        if (!items_json || !config_json || !output) {
            return {NP_ERR_NULL_PTR, "null pointer argument"};
        }
        std::string result = nipaplay::native::similarity_check_batch_json(
            std::string(items_json), std::string(config_json));
        *output = np_string_alloc(result);
        if (!output->data) {
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
        if (!text_a || !text_b) return 0.0;
        return nipaplay::native::danmaku_pair_similarity(
            std::string(text_a), std::string(text_b), use_pinyin != 0);
    } catch (...) {
        return 0.0;
    }
}
