#pragma once
#include <stdint.h>

typedef uint8_t uchar;
typedef uint16_t ushort;
typedef uint32_t uint;
typedef uint64_t ulong;

class SimilarityEngine;

// ===== Opaque C API =====
#ifdef __cplusplus
extern "C" {
#endif

/// 创建引擎实例（堆分配，含 ~4MB scratch buffer）
SimilarityEngine* sim_engine_create();

/// 销毁引擎实例
void sim_engine_destroy(SimilarityEngine* engine);

/// 初始化查重块（use_pinyin/cross_mode 用 int 代替 bool，确保 FFI 跨语言安全）
void sim_engine_begin_chunk(
    SimilarityEngine* engine,
    ushort* str_buf,
    int max_dist, int max_cosine,
    int use_pinyin, int cross_mode
);

/// 逐条检测，返回打包结果（0=不相似）
uint sim_engine_check_similar(
    SimilarityEngine* engine,
    uint mode, uint index_l
);

/// 锁定索引范围
void sim_engine_begin_index_lock(SimilarityEngine* engine);

/// 强制插入：将当前 str_buf 中的内容作为新条目插入 nearby_danmu_，
/// 更新 precise_matcher_ 哈希表。用于 Rust 侧拒绝窗口外匹配后，
/// 将被拒绝的弹幕作为新组代表插入引擎，避免 precise_matcher_ 死循环。
void sim_engine_force_insert(SimilarityEngine* engine, uint mode);

/// 重置引擎状态
void sim_engine_reset(SimilarityEngine* engine);

#ifdef __cplusplus
}
#endif
