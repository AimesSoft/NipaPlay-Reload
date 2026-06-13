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
// 通用指针释放 — 用于 Dart NativeFinalizer 释放 FFI 分配的缓冲区
NIPAPLAY_NATIVE_EXPORT void np_free_ptr(void* ptr);

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

// ──── 弹幕相似度引擎：SimilarityEngine（有状态对象，复用 ~4 MB scratch buffer）──

// 创建相似度引擎实例（~4 MB 内存，含 ed_a_/ed_b_ scratch buffer）
// 返回不透明句柄，Dart 侧通过 NativeFinalizer 自动释放
NIPAPLAY_NATIVE_EXPORT NpHandle np_sim_create(void);

// 销毁相似度引擎实例，释放 ~4 MB scratch buffer
NIPAPLAY_NATIVE_EXPORT void np_sim_destroy(NpHandle handle);

// 批量查重：使用已有引擎实例，输入弹幕 JSON + 配置 JSON，返回结果 JSON
// 引擎实例复用 scratch buffer，避免每次调用分配 ~4 MB
NIPAPLAY_NATIVE_EXPORT NpResult np_sim_check_batch(
    NpHandle handle, const char* items_json, const char* config_json, NpString* output);

// 单对相似度：输入两段文本 + 拼音开关，返回 0.0-1.0 分数
// 内部创建临时引擎，适用于低频调用
NIPAPLAY_NATIVE_EXPORT double np_sim_pair_similarity(
    const char* text_a, const char* text_b, int32_t use_pinyin);

// ──── 弹幕解析模块：DanmakuParser ────

// 解析 Bilibili 弹幕 XML，返回预序列化 JSON
// 输出格式: {"count":N,"comments":[{"t":...,"c":...,"y":...,"r":...,"fontSize":...,"originalType":...},...]}
// xml_content: UTF-8 XML 字符串指针
// content_len: 字符串字节长度（不含 null terminator），int64_t 避免大文件溢出
// output_json: 输出参数，调用者预分配 NpString 结构
// 返回: NpResult，成功时 output_json 包含 JSON 字符串
NIPAPLAY_NATIVE_EXPORT NpResult np_danmaku_parse_xml(
    const char* xml_content, int64_t content_len,
    NpString* output_json);

// 解析弹幕 JSON 数组，返回标准化 JSON
// 输出格式: {"count":N,"comments":[{"time":...,"content":...,"type":...,"color":...,...},...]}
// 支持双源字段映射: t/time, c/content, y/type, r/color
// 保留所有非标准额外字段
// json_content: UTF-8 JSON 字符串指针（顶层为数组）
// content_len: 字符串字节长度，int64_t 避免大文件溢出
// output_json: 输出参数
NIPAPLAY_NATIVE_EXPORT NpResult np_danmaku_parse_json(
    const char* json_content, int64_t content_len,
    NpString* output_json);

// ──── 字幕解析模块：SubtitleParser ────

// 字幕条目 — 与 Dart SubtitleEntry 对应
// content/style/name 为 NpString，由 np_subtitle_free_result 统一释放
typedef struct NpSubtitleEntry {
    int32_t start_time_ms;
    int32_t end_time_ms;
    NpString content;      // UTF-8 字幕文本
    NpString style;        // ASS 样式名，默认 "Default"
    NpString name;         // ASS 角色名，默认 ""
} NpSubtitleEntry;

// 解析结果 — 堆分配，由 np_subtitle_free_result 统一释放
// format_code: 0=ass, 1=srt, 2=subviewer, 3=microdvd, -1=unknown
typedef struct NpSubtitleParseResult {
    NpResultCode code;
    const char* error_message;    // 仅 code != NP_OK 时有效，独立堆分配（由 np_subtitle_free_result 释放）
    NpSubtitleEntry* entries;     // 条目数组（堆分配）
    int32_t entry_count;          // 条目数
    int32_t format_code;          // 字幕格式编码
    NpString detected_encoding;   // 检测到的编码名（UTF-8）
} NpSubtitleParseResult;

// 解析字节数据（Dart 侧提供已读取的字节 + 可选格式/路径提示）
// hint_path: 可选文件路径，用于编码/格式检测提示（如含 "big5" 优先 Big5），
//            可传 NULL
// 返回: 堆分配的 NpSubtitleParseResult*，需由 np_subtitle_free_result 释放
NIPAPLAY_NATIVE_EXPORT NpSubtitleParseResult* np_subtitle_parse_bytes(
    const uint8_t* data, int32_t len, const char* hint_path);

// 释放解析结果（释放 entries 数组中所有 NpString + entries + result 本身）
NIPAPLAY_NATIVE_EXPORT void np_subtitle_free_result(
    NpSubtitleParseResult* result);

#ifdef __cplusplus
}
#endif
