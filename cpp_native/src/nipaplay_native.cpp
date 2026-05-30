#include <exception>
#include <new>

#include "nipaplay_native/nipaplay_native.h"
#include "nipaplay_native/types.h"
#include "example_calculator.h"

// ──── 辅助：NpString 内部分配（C++ 内部函数，非 extern "C"） ────
NpString np_string_alloc(const std::string& s);

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
        return {NP_ERR_INTERNAL, e.what()};
    } catch (...) {
        return {NP_ERR_INTERNAL, "unknown C++ exception"};
    }
}
