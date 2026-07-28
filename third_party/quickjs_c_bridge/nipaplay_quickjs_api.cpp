#include "quickjs/quickjs.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <new>

#ifdef _MSC_VER
#define NP_QJS_EXPORT __declspec(dllexport)
#else
#define NP_QJS_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

using NpQjsBridgeCallback =
    char *(*)(intptr_t runtime_id, const char *channel, const char *message);

struct NpQjsHandle {
  JSRuntime *runtime;
  JSContext *context;
  NpQjsBridgeCallback bridge;
  intptr_t runtime_id;
};

static char *np_qjs_copy_string(const char *value) {
  if (value == nullptr) {
    return nullptr;
  }
  const size_t length = std::strlen(value);
  auto *copy = static_cast<char *>(std::malloc(length + 1));
  if (copy == nullptr) {
    return nullptr;
  }
  std::memcpy(copy, value, length + 1);
  return copy;
}

static JSValue np_qjs_send_message(JSContext *context,
                                   JSValueConst,
                                   int argc,
                                   JSValueConst *argv) {
  auto *handle = static_cast<NpQjsHandle *>(JS_GetContextOpaque(context));
  if (handle == nullptr || handle->bridge == nullptr || argc < 2) {
    return JS_NULL;
  }

  const char *channel = JS_ToCString(context, argv[0]);
  const char *message = JS_ToCString(context, argv[1]);
  if (channel == nullptr || message == nullptr) {
    if (channel != nullptr) {
      JS_FreeCString(context, channel);
    }
    if (message != nullptr) {
      JS_FreeCString(context, message);
    }
    return JS_NULL;
  }

  char *encoded_result =
      handle->bridge(handle->runtime_id, channel, message);
  JS_FreeCString(context, channel);
  JS_FreeCString(context, message);
  if (encoded_result == nullptr) {
    return JS_NULL;
  }

  JSValue result = JS_ParseJSON(
      context,
      encoded_result,
      std::strlen(encoded_result),
      "<dart-bridge>");
  std::free(encoded_result);
  if (JS_IsException(result)) {
    JS_FreeValue(context, result);
    return JS_NULL;
  }
  return result;
}

extern "C" {

NP_QJS_EXPORT NpQjsHandle *np_qjs_create(NpQjsBridgeCallback bridge,
                                         intptr_t runtime_id) {
  auto *handle = new (std::nothrow) NpQjsHandle{
      JS_NewRuntime(),
      nullptr,
      bridge,
      runtime_id,
  };
  if (handle == nullptr || handle->runtime == nullptr) {
    delete handle;
    return nullptr;
  }

  JS_SetMemoryLimit(handle->runtime, 64 * 1024 * 1024);
  JS_SetMaxStackSize(handle->runtime, 1024 * 1024);
  handle->context = JS_NewContext(handle->runtime);
  if (handle->context == nullptr) {
    JS_FreeRuntime(handle->runtime);
    delete handle;
    return nullptr;
  }

  JS_SetContextOpaque(handle->context, handle);
  JSValue global = JS_GetGlobalObject(handle->context);
  JS_SetPropertyStr(
      handle->context,
      global,
      "sendMessage",
      JS_NewCFunction(
          handle->context,
          np_qjs_send_message,
          "sendMessage",
          2));
  JS_FreeValue(handle->context, global);
  return handle;
}

NP_QJS_EXPORT int32_t np_qjs_evaluate(NpQjsHandle *handle,
                                      const char *code,
                                      intptr_t code_length,
                                      char **result,
                                      char **error) {
  if (result != nullptr) {
    *result = nullptr;
  }
  if (error != nullptr) {
    *error = nullptr;
  }
  if (handle == nullptr || handle->context == nullptr || code == nullptr) {
    if (error != nullptr) {
      *error = np_qjs_copy_string("Invalid QuickJS runtime or source");
    }
    return 1;
  }

  JS_UpdateStackTop(handle->runtime);
  JSValue value = JS_Eval(
      handle->context,
      code,
      static_cast<size_t>(code_length),
      "<nipaplay-plugin>",
      JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(value)) {
    JS_FreeValue(handle->context, value);
    JSValue exception = JS_GetException(handle->context);
    const char *message = JS_ToCString(handle->context, exception);
    if (error != nullptr) {
      *error = np_qjs_copy_string(
          message == nullptr ? "QuickJS evaluation failed" : message);
    }
    if (message != nullptr) {
      JS_FreeCString(handle->context, message);
    }
    JS_FreeValue(handle->context, exception);
    return 1;
  }

  const char *string_value = JS_ToCString(handle->context, value);
  if (result != nullptr) {
    *result = np_qjs_copy_string(
        string_value == nullptr ? "null" : string_value);
  }
  if (string_value != nullptr) {
    JS_FreeCString(handle->context, string_value);
  }
  JS_FreeValue(handle->context, value);
  return 0;
}

NP_QJS_EXPORT void np_qjs_dispose(NpQjsHandle *handle) {
  if (handle == nullptr) {
    return;
  }
  if (handle->context != nullptr) {
    JS_SetContextOpaque(handle->context, nullptr);
    JS_FreeContext(handle->context);
  }
  if (handle->runtime != nullptr) {
    JS_FreeRuntime(handle->runtime);
  }
  delete handle;
}

NP_QJS_EXPORT void np_qjs_free_string(char *value) {
  std::free(value);
}

}
