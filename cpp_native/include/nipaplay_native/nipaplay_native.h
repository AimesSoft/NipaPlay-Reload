#pragma once
#include "export.h"
#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

// ──── 库级 API ────
NIPAPLAY_NATIVE_EXPORT int32_t np_get_version(void);

// ──── 内存管理 ────
NIPAPLAY_NATIVE_EXPORT void np_string_free(NpString* str);

// ──── 示例模块：ExampleCalculator ────
NIPAPLAY_NATIVE_EXPORT NpHandle np_example_create(void);
NIPAPLAY_NATIVE_EXPORT void     np_example_destroy(NpHandle handle);
NIPAPLAY_NATIVE_EXPORT int32_t  np_example_add(NpHandle handle, int32_t a, int32_t b);
NIPAPLAY_NATIVE_EXPORT NpResult np_example_process_text(
    NpHandle handle, const char* input, NpString* output);

// ──── 弹幕布局引擎：DanmakuLayoutEngine ────

// 弹幕条目输入结构（Dart 侧预测量文本宽度后填入）
// 字段按对齐排列：double → int32，最小化填充
typedef struct NpDanmakuItem {
    double time_seconds;             // 弹幕出现时间
    double text_width;               // ★ Dart 侧 TextPainter 预测量
    double font_size_multiplier;     // 字体大小倍率（合并弹幕用）
    int32_t type;                    // 0=scroll, 1=top, 2=bottom
    int32_t is_me;                   // 是否用户自己（0/1）
    int32_t stack_hash;              // 堆叠轨道 hash（Dart 预计算: text.hashCode ^ time.toInt()）
    int32_t _reserved;               // 对齐保留，确保 struct 大小为 8 的倍数
} NpDanmakuItem;

// 布局结果输出结构（每帧由 np_layout_frame 写入）
typedef struct NpLayoutResult {
    double y_position;               // y 坐标
    double scroll_speed;             // 滚动速度（仅 scroll 类型有效，Dart 用于算 x）
    int32_t item_index;              // 对应输入数组中的索引
    int32_t track_index;             // 分配的轨道编号（-1=未分配）
} NpLayoutResult;

// 零拷贝帧输出结构（C++ 端预计算 x / offstageX / textWidth / type，
// Dart 侧无需回查 items 数组做 elapsed/switch/除法运算）
typedef struct NpFrameRawOutput {
    double y_position;               // y 坐标
    double x;                        // C++ 预计算 x 坐标
    double scroll_speed;             // 滚动速度（scroll 有效，static=0）
    double offstage_x;               // 初始屏幕外位置
    double text_width;               // 文本宽度（视口剔除 + PositionedDanmakuItem.width）
    int32_t item_index;              // 对应输入数组索引
    int32_t type;                    // 0=scroll, 1=top, 2=bottom
    int32_t _reserved1;              // 对齐保留
    int32_t _reserved2;              // 对齐保留
} NpFrameRawOutput;

// 引擎生命周期
NIPAPLAY_NATIVE_EXPORT NpHandle np_layout_create(void);
NIPAPLAY_NATIVE_EXPORT void     np_layout_destroy(NpHandle handle);

// 配置引擎（Dart 侧预算文本宽度后，传入弹幕结构体数组 + 参数）
// items 指针仅在调用期间有效，C++ 侧会拷贝数据
NIPAPLAY_NATIVE_EXPORT NpResult np_layout_configure(
    NpHandle handle,
    const NpDanmakuItem* items, int32_t item_count,
    double width, double height,
    double font_size, double display_area,
    double scroll_duration, double static_duration,
    int32_t allow_stacking,
    double base_danmaku_height,
    double base_track_height);

// 获取指定时刻的活跃弹幕布局结果（每帧同步调用）
// output_items 由调用者预分配，output_count 返回实际数量
NIPAPLAY_NATIVE_EXPORT NpResult np_layout_frame(
    NpHandle handle, double current_time,
    NpLayoutResult* output_items, int32_t output_capacity,
    int32_t* output_count);

// 零拷贝帧查询：C++ 端预计算 x / offstageX / textWidth / type，
// Dart 侧无需回查 items 数组做 elapsed/switch/除法运算
// output_items 由调用者预分配，output_count 返回实际数量
NIPAPLAY_NATIVE_EXPORT NpResult np_layout_frame_raw(
    NpHandle handle, double current_time,
    NpFrameRawOutput* output_items, int32_t output_capacity,
    int32_t* output_count);

// ──── 弹幕相似度引擎：SimilarityEngine ────

// 批量查重：输入弹幕 JSON + 配置 JSON，返回结果 JSON（NpString，用 np_string_free 释放）
NIPAPLAY_NATIVE_EXPORT NpResult np_sim_check_batch(
    const char* items_json, const char* config_json, NpString* output);

// 单对相似度：输入两段文本 + 拼音开关，返回 0.0-1.0 分数
NIPAPLAY_NATIVE_EXPORT double np_sim_pair_similarity(
    const char* text_a, const char* text_b, int32_t use_pinyin);

#ifdef __cplusplus
}
#endif
