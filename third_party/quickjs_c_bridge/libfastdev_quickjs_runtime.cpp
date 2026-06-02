#include "quickjs/quickjs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef __ANDROID__
#include <android/log.h>
#else
#define __android_log_print(a, b, c, d)
#endif

#ifdef _MSC_VER
#define DLLEXPORT __declspec(dllexport)
#else
#define DLLEXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

int QUICKJS_RUNTIME_DEBUG_ENABLED = 0;

int ONE_VALUE = 0;

extern "C"
{

    DLLEXPORT int doReturnOne()
    {
        ONE_VALUE += 3;
        return ONE_VALUE;
    }
    DLLEXPORT JSRuntime *JS_NewRuntimeDartBridge(void)
    {
        JSRuntime *runtime = JS_NewRuntime();
        JS_SetGCThreshold(runtime, (size_t)-1); // disable GC - to prevent GC disallocate variables
                                                // yet in use in the Dart side
        JS_SetMemoryLimit(runtime, 0x4000000);  // 64 Mo
        //JS_SetMemoryLimit(runtime, -1); is the default
        return runtime;
    }

#define QUICKJS_CHANNEL_CONSOLELOG 0;
#define QUICKJS_CHANNEL_SETTIMEOUT 1;
#define QUICKJS_CHANNEL_SENDNATIVE 2;

    typedef JSValue *(*ChannelFunc)(const JSContext *ctx, const char *channel, const char *message);
    struct channel
    {
        char *name;
        JSContext *ctx;
        ChannelFunc func;
        int assigned;
    };

    struct channel channel_functions[10] = {/*{"cat", cat_func}, {"dog", dog_func}, {NULL, NULL}*/
                                            {NULL, NULL, 0},
                                            {NULL, NULL, 0},
                                            {NULL, NULL, 0},
                                            {NULL, NULL, 0},
                                            {NULL, NULL, 0},
                                            {NULL, NULL, 0},
                                            {NULL, NULL, 0},
                                            {NULL, NULL, 0},
                                            {NULL, NULL, 0},
                                            {NULL, NULL, 0}};

    // where cat_func is declared int cat_func(const char **args);.
    // You can search the list with

    int contextsLength = 0;

    static JSValue CChannelFunction(JSContext *ctx, JSValueConst this_val,
                                    int argc, JSValueConst *argv)
    {

        const char *channelName = JS_ToCString(ctx, argv[0]);
        const char *message = JS_ToCString(ctx, argv[1]);

        JSValue jsResult = JS_NULL;
        // while(cur->ctx) {
        //     //if(!strcmp(cur->name, channelName)) {
        //     if (cur->ctx == ctx && cur->assigned == 1) {
        //         JS_Eval(ctx, "console.log('Aqui no CChannelFunction3');", 40,"arquivo.js",0);
        //         result = cur->func(channelName, message);
        //         JS_Eval(ctx, "console.log('Aqui no CChannelFunction4');", 40,"arquivo.js",0);
        //         jsResult = JS_NewString(ctx, result);
        //         JS_Eval(ctx, "console.log('Aqui no CChannelFunction5');", 40,"arquivo.js",0);
        //     }
        // }

        int idxChannel = 0;
        if (strcmp("SendNative", channelName) == 0)
        {
            idxChannel = QUICKJS_CHANNEL_SENDNATIVE;
        }
        else if (strcmp("ConsoleLog", channelName) == 0)
        {
            idxChannel = QUICKJS_CHANNEL_CONSOLELOG;
        }
        if (strcmp("SetTimeout", channelName) == 0)
        {
            idxChannel = QUICKJS_CHANNEL_SETTIMEOUT;
        }

        if (channel_functions[idxChannel].assigned == 1)
        {
            ChannelFunc funcCaller = channel_functions[idxChannel].func;

            if (funcCaller != nullptr)
            {
                jsResult = *funcCaller(ctx, channelName, message);
            }
            else
            {
                jsResult = JS_NewString(ctx, "No function found");
            }
        }

        return jsResult;
    }

    JSValue stringifyFn;

    DLLEXPORT JSContext *JS_NewContextDartBridge(
        JSRuntime *rt,
        ChannelFunc consoleLogChannelFunction,
        ChannelFunc setTimeoutChannelFunction,
        ChannelFunc sendNativeChannelFunction)
    {
        JSContext *ctx;
        ctx = JS_NewContext(rt);

        // create the QuickJS Function passing the CChannelFunction ;
        // register the function jsBridgeFunction into the global object
        JSValue globalObject = JS_GetGlobalObject(ctx);

        stringifyFn = JS_Eval(
            ctx,
            "function simpleStringify(obj) { return JSON.stringify(obj);}simpleStringify;",
            strlen("function simpleStringify(obj) { return JSON.stringify(obj);}"),
            "f1.js",
            0);

        JS_SetPropertyStr(
            ctx,
            globalObject,
            "FLUTTER_JS_NATIVE_BRIDGE_sendMessage",
            JS_NewCFunction(ctx, CChannelFunction, "FLUTTER_JS_NATIVE_BRIDGE_sendMessage", 2));

        if (consoleLogChannelFunction)
        {
            channel_functions[0].func = consoleLogChannelFunction;
            channel_functions[0].ctx = ctx;
            channel_functions[0].name = (char *)"ConsoleLog";
            channel_functions[0].assigned = 1;

            channel_functions[1].func = setTimeoutChannelFunction;
            channel_functions[1].ctx = ctx;
            channel_functions[1].name = (char *)"SetTimeout";
            channel_functions[1].assigned = 1;

            // store in the function register the dartChannelFunction passed
            channel_functions[2].func = sendNativeChannelFunction;
            channel_functions[2].ctx = ctx;
            channel_functions[2].name = (char *)"SendNative";
            channel_functions[2].assigned = 1;

            contextsLength = 3;
        }

        // JS_FreeValue(ctx, globalObject);

        // JS_FreeValue(ctx, stringifyFn);

        // returns the generated context
        return ctx;
    }

    DLLEXPORT JSValue *copyToHeap(JSValueConst value)
    {
        auto *result = static_cast<JSValue *>(malloc(sizeof(JSValueConst)));
        if (result)
        {
            memcpy(result, &value, sizeof(JSValueConst));
        }
        return result;
    }
    DLLEXPORT const void *JSEvalWrapper(JSContext *ctx, const char *input, size_t input_len,
                                        const char *filename, int eval_flags,
                                        int *errors, JSValue *result, char **stringResult)
    {
        JSRuntime *rt = JS_GetRuntime(ctx);
        JS_UpdateStackTop(rt);

        // __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "Before Eval: %p", result);
        result = new JSValue(JS_Eval(ctx, input, input_len, filename, eval_flags));
        // __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "After Eval: %p", result);
        *errors = 0;

        if (JS_IsException(*result) == 1)
        {
            // __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "Inside is exception: %p", result);
            JS_FreeValue(ctx, *result);
            *errors = 1;
            * result = JS_GetException(ctx);
            *stringResult = (char *)JS_ToCString(ctx, *result);
            // __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "After get  exception: %p", result);
            return nullptr;
        }
        // __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "Before string result: %p", stringResult);
        *stringResult = (char *)JS_ToCString(ctx, *result);
        // __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "After string result: %p", stringResult);
        return nullptr;
    }

    DLLEXPORT void *JS_GetNullValue(JSContext *ctx, JSValue *result)
    {
        result = copyToHeap(JS_Eval(
            ctx,
            "null",
            4,
            "f1.js",
            0));
        return nullptr;
    }


    DLLEXPORT int32_t jsIsFunction(JSContext *ctx, JSValueConst *val)
    {
        return JS_IsFunction(ctx, *val);
    }

    // used in method callFunction in quickjs_method_bindings
    DLLEXPORT int callJsFunction1Arg(JSContext *ctx, JSValueConst *function, JSValueConst *object, JSValueConst *result, char **stringResult)
    {
        JSRuntime *rt = JS_GetRuntime(ctx);
        JS_UpdateStackTop(rt);
        JSValue globalObject = JS_GetGlobalObject(ctx);
        // JSValue function = JS_GetPropertyStr(ctx, globalObject, functionName);

        result = copyToHeap(JS_Call(ctx, *function, globalObject, 1, object));

        int successOperation = 1;

        if (JS_IsException(*result) == 1)
        {
            successOperation = 0;
            result = copyToHeap(JS_GetException(ctx));
        }
        *stringResult = (char *)JS_ToCString(ctx, *result);
        return successOperation;
    }

    DLLEXPORT int getTypeTag(JSValue *jsValue)
    {
        if (jsValue)
        {
            return JS_VALUE_GET_TAG(*jsValue);
        }
        else
        {
            return JS_TAG_NULL;
        }
    }

    DLLEXPORT int JS_IsArrayDartWrapper(JSContext *ctx, JSValueConst *val)
    {
        return JS_IsArray(ctx, *val);
    }

    DLLEXPORT int JS_JSONStringifyDartWrapper(
        JSContext *ctx,
        JSValue *obj, JSValueConst *result, char **stringResult)
    {
        if (QUICKJS_RUNTIME_DEBUG_ENABLED == 1)
        {
            __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "JS_JSONStringifyDartWrapper %p", result);
        }
        JSValue globalObject = JS_GetGlobalObject(ctx);
        if (QUICKJS_RUNTIME_DEBUG_ENABLED == 1)
        {
            __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "JS_JSONStringifyDartWrapper2 %p", result);
        }
        if (JS_IsUndefined(*obj) == 1)
        {
            if (QUICKJS_RUNTIME_DEBUG_ENABLED == 1)
            {
                __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "JS_JSONStringifyDartWrapper3 %p", result);
            }
            *stringResult = (char *)"undefined";
            return 0;
        }
        else if (JS_IsNull(*obj) == 1)
        {
            if (QUICKJS_RUNTIME_DEBUG_ENABLED == 1)
            {
                __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "JS_JSONStringifyDartWrapper4 %p", result);
            }
            *stringResult = (char *)"null";
            return 0;
        }
        else
        {
            if (QUICKJS_RUNTIME_DEBUG_ENABLED == 1)
            {
                __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "JS_JSONStringifyDartWrapper5 %p", result);
            }
            result = copyToHeap(JS_Call(ctx, stringifyFn, globalObject, 1, obj));
            *stringResult = (char *)JS_ToCString(ctx, *result);
            if (QUICKJS_RUNTIME_DEBUG_ENABLED == 1)
            {
                __android_log_print(ANDROID_LOG_DEBUG, "LOG_TAG", "JS_JSONStringifyDartWrapper6 %p", result);
            }
            return 1;
        }
    }

    enum JSChannelType
    {
        JSChannelType_METHON = 0,
        JSChannelType_MODULE = 1,
        JSChannelType_PROMISE_TRACK = 2,
        JSChannelType_FREE_OBJECT = 3,
    };

    typedef void *JSChannel(JSContext *ctx, size_t type, void *argv);

    DLLEXPORT JSValue *jsThrow(JSContext *ctx, JSValue *obj)
    {
        return new JSValue(JS_Throw(ctx, JS_DupValue(ctx, *obj)));
    }

    DLLEXPORT JSValue *jsEXCEPTION()
    {
        return new JSValue(JS_EXCEPTION);
    }

    DLLEXPORT JSValue *jsUNDEFINED()
    {
        return new JSValue(JS_UNDEFINED);
    }

    DLLEXPORT JSValue *jsNULL()
    {
        return new JSValue(JS_NULL);
    }

    JSModuleDef *js_module_loader(
        JSContext *ctx,
        const char *module_name, void *opaque)
    {
        JSRuntime *rt = JS_GetRuntime(ctx);
        JSChannel *channel = (JSChannel *)JS_GetRuntimeOpaque(rt);
        const char *str = (char *)channel(ctx, JSChannelType_MODULE, (void *)module_name);
        if (str == 0)
            return NULL;
        JSValue func_val = JS_Eval(ctx, str, strlen(str), module_name, JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
        if (JS_IsException(func_val))
            return NULL;
        /* the module is already referenced, so we must free it */
        JSModuleDef *m = (JSModuleDef *)JS_VALUE_GET_PTR(func_val);
        JS_FreeValue(ctx, func_val);
        return m;
    }

    JSValue js_channel(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv, int magic, JSValue *func_data)
    {
        JSRuntime *rt = JS_GetRuntime(ctx);
        JSChannel *channel = (JSChannel *)JS_GetRuntimeOpaque(rt);
        void *data[4];
        data[0] = &this_val;
        data[1] = &argc;
        data[2] = argv;
        data[3] = func_data;
        return *(JSValue *)channel(ctx, JSChannelType_METHON, data);
    }

    void js_promise_rejection_tracker(JSContext *ctx, JSValueConst promise,
                                      JSValueConst reason,
                                      JS_BOOL is_handled, void *opaque)
    {
        if (is_handled)
            return;
        JSRuntime *rt = JS_GetRuntime(ctx);
        JSChannel *channel = (JSChannel *)JS_GetRuntimeOpaque(rt);
        channel(ctx, JSChannelType_PROMISE_TRACK, &reason);
    }

    DLLEXPORT JSRuntime *jsNewRuntime(JSChannel channel)
    {
        JSRuntime *rt = JS_NewRuntime();
        JS_SetRuntimeOpaque(rt, (void *)channel);
        JS_SetHostPromiseRejectionTracker(rt, js_promise_rejection_tracker, nullptr);
        JS_SetModuleLoaderFunc(rt, nullptr, js_module_loader, nullptr);
        return rt;
    }

    DLLEXPORT uint32_t jsNewClass(JSContext *ctx, const char *name)
    {
        JSClassID QJSClassId = 0;
        JS_NewClassID(&QJSClassId);
        JSRuntime *rt = JS_GetRuntime(ctx);
        if (!JS_IsRegisteredClass(rt, QJSClassId))
        {
            JSClassDef def{
                name,
                // destructor
                [](JSRuntime *rt, JSValue obj) noexcept {
                    JSClassID classid = JS_GetClassID(obj);
                    void *opaque = JS_GetOpaque(obj, classid);
                    JSChannel *channel = (JSChannel *)JS_GetRuntimeOpaque(rt);
                    if (channel == nullptr)
                        return;
                    channel((JSContext *)rt, JSChannelType_FREE_OBJECT, opaque);
                }};
            int e = JS_NewClass(rt, QJSClassId, &def);
            if (e < 0)
            {
                JS_ThrowInternalError(ctx, "Cant register class %s", name);
                return 0;
            }
        }
        return QJSClassId;
    }

    DLLEXPORT void *jsGetObjectOpaque(JSValue *obj, uint32_t classid)
    {
        return JS_GetOpaque(*obj, classid);
    }

    DLLEXPORT JSValue *jsNewObjectClass(JSContext *ctx, uint32_t QJSClassId, void *opaque)
    {
        auto jsobj = new JSValue(JS_NewObjectClass(ctx, QJSClassId));
        if (JS_IsException(*jsobj))
            return jsobj;
        JS_SetOpaque(*jsobj, opaque);
        return jsobj;
    }
    DLLEXPORT void jsSetMaxStackSize(JSRuntime *rt, size_t stack_size)
    {
        JS_SetMaxStackSize(rt, stack_size);
    }

    DLLEXPORT void jsFreeRuntime(JSRuntime *rt)
    {
        JS_SetRuntimeOpaque(rt, nullptr);
        JS_FreeRuntime(rt);
    }

    DLLEXPORT JSValue *jsNewCFunction(JSContext *ctx, JSValue *funcData)
    {
        return new JSValue(JS_NewCFunctionData(ctx, js_channel, 0, 0, 1, funcData));
    }

    DLLEXPORT JSContext *jsNewContext(JSRuntime *rt)
    {
        JSContext *ctx = JS_NewContext(rt);
        return ctx;
    }

    DLLEXPORT void jsFreeContext(JSContext *ctx)
    {
        JS_FreeContext(ctx);
    }

    DLLEXPORT JSRuntime *jsGetRuntime(JSContext *ctx)
    {
        return JS_GetRuntime(ctx);
    }

    DLLEXPORT JSValue *jsEval(JSContext *ctx, const char *input, size_t input_len, const char *filename, int32_t eval_flags)
    {
        JSRuntime *rt = JS_GetRuntime(ctx);
        JS_UpdateStackTop(rt);
        JSValue *ret = new JSValue(JS_Eval(ctx, input, input_len, filename, eval_flags));
        return ret;
    }

    DLLEXPORT int32_t jsValueGetTag(JSValue *val)
    {
        return JS_VALUE_GET_TAG(*val);
    }

    DLLEXPORT void *jsValueGetPtr(JSValue *val)
    {
        return JS_VALUE_GET_PTR(*val);
    }

    DLLEXPORT int32_t jsTagIsFloat64(int32_t tag)
    {
        return JS_TAG_IS_FLOAT64(tag);
    }

    DLLEXPORT JSValue *jsNewBool(JSContext *ctx, int32_t val)
    {
        return new JSValue(JS_NewBool(ctx, val));
    }

    DLLEXPORT JSValue *jsNewInt64(JSContext *ctx, int64_t val)
    {
        return new JSValue(JS_NewInt64(ctx, val));
    }

    DLLEXPORT JSValue *jsNewFloat64(JSContext *ctx, double val)
    {
        return new JSValue(JS_NewFloat64(ctx, val));
    }

    DLLEXPORT JSValue *jsNewString(JSContext *ctx, const char *str)
    {
        return new JSValue(JS_NewString(ctx, str));
    }

    DLLEXPORT JSValue *jsNewArrayBufferCopy(JSContext *ctx, const uint8_t *buf, size_t len)
    {
        return new JSValue(JS_NewArrayBufferCopy(ctx, buf, len));
    }

    DLLEXPORT JSValue *jsNewArray(JSContext *ctx)
    {
        return new JSValue(JS_NewArray(ctx));
    }

    DLLEXPORT JSValue *jsNewObject(JSContext *ctx)
    {
        return new JSValue(JS_NewObject(ctx));
    }

    DLLEXPORT void jsFreeValue(JSContext *ctx, JSValue *v, int32_t free)
    {
        JS_FreeValue(ctx, *v);
        if (free)
            delete v;
    }

    DLLEXPORT void jsFreeValueRT(JSRuntime *rt, JSValue *v, int32_t free)
    {
        JS_FreeValueRT(rt, *v);
        if (free)
            delete v;
    }

    DLLEXPORT JSValue *jsDupValue(JSContext *ctx, JSValueConst *v)
    {
        return new JSValue(JS_DupValue(ctx, *v));
    }

    DLLEXPORT JSValue *jsDupValueRT(JSRuntime *rt, JSValue *v)
    {
        return new JSValue(JS_DupValueRT(rt, *v));
    }

    DLLEXPORT int32_t jsToBool(JSContext *ctx, JSValueConst *val)
    {
        return JS_ToBool(ctx, *val);
    }

    DLLEXPORT int64_t jsToInt64(JSContext *ctx, JSValueConst *val)
    {
        int64_t p;
        JS_ToInt64(ctx, &p, *val);
        return p;
    }

    DLLEXPORT double jsToFloat64(JSContext *ctx, JSValueConst *val)
    {
        double p;
        JS_ToFloat64(ctx, &p, *val);
        return p;
    }

    DLLEXPORT const char *jsToCString(JSContext *ctx, JSValueConst *val)
    {
        JSRuntime *rt = JS_GetRuntime(ctx);
        JS_UpdateStackTop(rt);
        const char *ret = JS_ToCString(ctx, *val);
        return ret;
    }

    DLLEXPORT void jsFreeCString(JSContext *ctx, const char *ptr)
    {
        return JS_FreeCString(ctx, ptr);
    }

    DLLEXPORT uint8_t *jsGetArrayBuffer(JSContext *ctx, size_t *psize, JSValueConst *obj)
    {
        return JS_GetArrayBuffer(ctx, psize, *obj);
    }

    DLLEXPORT int32_t jsIsPromise(JSContext *ctx, JSValueConst *val)
    {
        return JS_IsPromise(ctx, *val);
    }

    DLLEXPORT int32_t jsIsArray(JSContext *ctx, JSValueConst *val)
    {
        return JS_IsArray(ctx, *val);
    }

    DLLEXPORT int32_t jsIsError(JSContext *ctx, JSValueConst *val)
    {
        return JS_IsError(ctx, *val);
    }

    DLLEXPORT JSValue *jsNewError(JSContext *ctx)
    {
        return new JSValue(JS_NewError(ctx));
    }

    DLLEXPORT JSValue *jsGetProperty(JSContext *ctx, JSValueConst *this_obj,
                                     JSAtom prop)
    {
        return new JSValue(JS_GetProperty(ctx, *this_obj, prop));
    }

    DLLEXPORT int32_t jsDefinePropertyValue(JSContext *ctx, JSValueConst *this_obj,
                                            JSAtom prop, JSValue *val, int32_t flags)
    {
        return JS_DefinePropertyValue(ctx, *this_obj, prop, *val, flags);
    }

    DLLEXPORT void jsFreeAtom(JSContext *ctx, JSAtom v)
    {
        JS_FreeAtom(ctx, v);
    }

    DLLEXPORT JSAtom jsValueToAtom(JSContext *ctx, JSValueConst *val)
    {
        return JS_ValueToAtom(ctx, *val);
    }

    DLLEXPORT JSValue *jsAtomToValue(JSContext *ctx, JSAtom val)
    {
        return new JSValue(JS_AtomToValue(ctx, val));
    }

    DLLEXPORT int32_t jsGetOwnPropertyNames(JSContext *ctx, JSPropertyEnum **ptab,
                                            uint32_t *plen, JSValueConst *obj, int32_t flags)
    {
        return JS_GetOwnPropertyNames(ctx, ptab, plen, *obj, flags);
    }

    DLLEXPORT JSAtom jsPropertyEnumGetAtom(JSPropertyEnum *ptab, int32_t i)
    {
        return ptab[i].atom;
    }

    DLLEXPORT uint32_t sizeOfJSValue()
    {
        return sizeof(JSValue);
    }

    DLLEXPORT void setJSValueList(JSValue *list, uint32_t i, JSValue *val)
    {
        list[i] = *val;
    }

    DLLEXPORT JSValue *jsCall(JSContext *ctx, JSValueConst *func_obj, JSValueConst *this_obj,
                              int32_t argc, JSValueConst *argv)
    {
        JSRuntime *rt = JS_GetRuntime(ctx);
        JS_UpdateStackTop(rt);
        JSValue *ret = new JSValue(JS_Call(ctx, *func_obj, *this_obj, argc, argv));
        return ret;
    }

    DLLEXPORT int32_t jsIsException(JSValueConst *val)
    {
        return JS_IsException(*val);
    }

    DLLEXPORT JSValue *jsGetException(JSContext *ctx)
    {
        return new JSValue(JS_GetException(ctx));
    }

    DLLEXPORT int32_t jsExecutePendingJob(JSRuntime *rt)
    {
        JS_UpdateStackTop(rt);
        JSContext *ctx;
        int ret = JS_ExecutePendingJob(rt, &ctx);
        return ret;
    }

    DLLEXPORT JSValue *jsNewPromiseCapability(JSContext *ctx, JSValue *resolving_funcs)
    {
        return new JSValue(JS_NewPromiseCapability(ctx, resolving_funcs));
    }

    DLLEXPORT void jsFree(JSContext *ctx, void *ptab)
    {
        js_free(ctx, ptab);
    }
}