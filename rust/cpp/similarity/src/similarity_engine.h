#pragma once
#include <cstdint>

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

/// 初始化查重块
void sim_engine_begin_chunk(
    SimilarityEngine* engine,
    ushort* str_buf,
    int max_dist, int max_cosine,
    bool use_pinyin, bool cross_mode
);

/// 逐条检测，返回打包结果（0=不相似）
uint sim_engine_check_similar(
    SimilarityEngine* engine,
    uint mode, uint index_l
);

/// 锁定索引范围
void sim_engine_begin_index_lock(SimilarityEngine* engine);

/// 重置引擎状态
void sim_engine_reset(SimilarityEngine* engine);

#ifdef __cplusplus
}
#endif
