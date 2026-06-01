#pragma once
#include <cstdint>
#include <cstring>
#include <vector>
#include <unordered_map>
#include <memory>
#include <string>
#include <algorithm>

namespace nipaplay::native {

// ──── 类型别名（与 pakku.js 原始代码一致） ────
using sim_uchar = uint8_t;
using sim_ushort = uint16_t;
using sim_uint = uint32_t;
using sim_ulong = uint64_t;

// ──── 拼音字典懒加载接口 ────
extern const std::unordered_map<sim_ushort, std::pair<sim_uchar, sim_uchar>>& get_pinyin_dict();

// ──── 常量 ────
constexpr int SIM_PINYIN_BASE = 0xe000;
constexpr int SIM_HASH_MOD = 1007;
constexpr int SIM_MAX_HASH_VAL = std::max(SIM_HASH_MOD * SIM_HASH_MOD, 1 << 16) + 7;
// NOTE: Each SimilarityEngine instance allocates ~4 MB for ed_a_ + ed_b_
//       (2 × 1,014,056 × sizeof(short) ≈ 3.87 MB). This is fine for desktop,
//       but should be monitored on memory-constrained Android 32-bit targets.
constexpr sim_uint SIM_MAX_IDX_RANGE = (1 << 19) - 3;
constexpr sim_uint SIM_MAX_DIST_VAL = (1 << 11) - 3;

// ──── 相似度引擎类 ────
// 从 pakku.js / NipaPlay Rust-C++ FFI 迁移的原生 C++ 实现。
// 负责弹幕去重核心算法：编辑距离、拼音距离、余弦相似度。
class SimilarityEngine {
public:
    SimilarityEngine();
    ~SimilarityEngine() = default;
    SimilarityEngine(const SimilarityEngine&) = delete;
    SimilarityEngine& operator=(const SimilarityEngine&) = delete;

    // ──── UnorderedContainer ────
    // 使用 scratch buffer (ed_a) 的频次容器
    template<typename T>
    struct UnorderedContainer {
        std::vector<std::pair<T, sim_ushort>> data{};
        int length{};
        short* ed_a;

        UnorderedContainer(short* ea): length(0), ed_a(ea) {}

        void push(T x) {
            length++;
            if(ed_a[x] == 0) {
                data.emplace_back(x, 1);
                ed_a[x] = static_cast<short>(data.size());
            } else {
                data[ed_a[x]-1].second++;
            }
        }
        void cleanup() {
            for(auto& p: data) {
                ed_a[p.first] = 0;
            }
        }
        void dispose() {
            data.clear();
        }
    };

    // ──── DanmuCacheline ────
    struct DanmuCacheline {
        sim_uint idx{};
        sim_uint mode{};
        std::vector<sim_ushort> orig{};
        UnorderedContainer<sim_ushort> str;
        UnorderedContainer<sim_ushort> pinyin;
        UnorderedContainer<sim_uint> gram;
        std::vector<sim_ulong> peers{};

        explicit DanmuCacheline(SimilarityEngine* engine,
                                const sim_ushort* s, sim_uint mode, sim_uint idx)
            : idx(idx), mode(mode)
            , str(engine->ed_a_.get())
            , pinyin(engine->ed_a_.get())
            , gram(engine->ed_a_.get())
            , peers({})
        {
            for(sim_ushort c = *s; c; c = *(++s)) {
                orig.push_back(c);
                str.push(c);
            }
            str.cleanup();

            if(engine->config_.use_pinyin) {
                const auto& pd = get_pinyin_dict();
                for(sim_ushort c: orig) {
                    auto cs = pd.find(c);
                    if(cs != pd.end()) {
                        pinyin.push(SIM_PINYIN_BASE + cs->second.first);
                        if(cs->second.second)
                            pinyin.push(SIM_PINYIN_BASE + cs->second.second);
                    } else {
                        if(c >= 'A' && c <= 'Z') c += 'a' - 'A';
                        pinyin.push(c);
                    }
                }
                pinyin.cleanup();
            }

            if(engine->config_.max_cosine <= 100 && !orig.empty()) {
                sim_uint clast = (*orig.crbegin()) % SIM_HASH_MOD;
                for(sim_uint c: orig) {
                    c = c % SIM_HASH_MOD;
                    gram.push(clast * SIM_HASH_MOD + c);
                    clast = c;
                }
                gram.cleanup();
            }
        }

        void dispose(SimilarityEngine* engine) {
            orig.clear();
            str.dispose();
            pinyin.dispose();
            gram.dispose();
            for(auto& peer: peers) {
                engine->precise_matcher_.erase(peer);
            }
            peers.clear();
        }
    };

    // ──── 配置 ────
    struct Config {
        int max_dist = 0;
        int max_cosine = 0;
        bool use_pinyin = false;
        bool cross_mode = false;
        sim_ushort* str_buf = nullptr;
        bool index_r_lock = false;
        int min_danmu_size = 0;
        sim_uint dispose_idx = 0;
    } config_;

    // ──── 精确匹配哈希 ────
    sim_ulong precise_matcher_hash(const sim_ushort* s, sim_ushort mode) {
        sim_ulong ret = mode;
        for(sim_ushort c = *s; c; c = *(++s)) {
            ret ^= c + 0x9e3779b9 + (ret << 6) + (ret >> 2);
        }
        return ret;
    }

    // ──── 编辑距离 ────
    int edit_distance(const UnorderedContainer<sim_ushort>& p,
                      const UnorderedContainer<sim_ushort>& q) {
        short* ea = ed_a_.get();
        for(const auto& item: p.data) ea[item.first] += item.second;
        for(const auto& item: q.data) ea[item.first] -= item.second;
        int ans = 0;
        for(const auto& item: p.data) { ans += std::abs(ea[item.first]); ea[item.first] = 0; }
        for(const auto& item: q.data) { ans += std::abs(ea[item.first]); ea[item.first] = 0; }
        return ans;
    }

    // ──── 余弦距离 ────
    float cosine_distance(const UnorderedContainer<sim_uint>& p,
                          const UnorderedContainer<sim_uint>& q) {
        short* ea = ed_a_.get();
        short* eb = ed_b_.get();
        for(const auto& item: p.data) ea[item.first] += item.second;
        for(const auto& item: q.data) eb[item.first] += item.second;
        int x=0, y=0, z=0;
        for(const auto& item: p.data) {
            int xa = ea[item.first], xb = eb[item.first];
            x += xa*xb; y += xa*xa; z += xb*xb;
            ea[item.first] = 0; eb[item.first] = 0;
        }
        for(const auto& item: q.data) {
            int xb = eb[item.first]; z += xb*xb; eb[item.first] = 0;
        }
        if(y<=0 || z<=0) return 0.0f;
        return static_cast<float>(x) * x / y / z;
    }

    // ──── CombinedReason 枚举 ────
    enum CombinedReason : sim_uint {
        combined_identical = 0,
        combined_edit_distance = 1,
        combined_pinyin_distance = 2,
        combined_cosine_distance = 3,
    };

    static sim_uint sim_result(CombinedReason reason, sim_uint dist, sim_uint target_idx) {
        return (reason << 30) | (std::min(dist, SIM_MAX_DIST_VAL) << 19) | target_idx;
    }

    // ──── 单对比较 ────
    sim_uint check_similar_single(const DanmuCacheline& p,
                                  const DanmuCacheline& q) {
        if(!config_.cross_mode && p.mode != q.mode)
            return 0;

        sim_uint idx_delta = p.idx - q.idx;
        sim_uint len_p = p.orig.size(), len_q = q.orig.size();
        sim_uint len_sum = len_p + len_q;

        if(p.orig == q.orig)
            return sim_result(combined_identical, 0, idx_delta);

        int edit_dis = 0;
        bool calc_edit_dis = std::abs(p.str.length - q.str.length) <= config_.max_dist;
        if(calc_edit_dis) {
            edit_dis = edit_distance(
                p.str,
                q.str);
            if(
                (len_sum < (sim_uint)config_.min_danmu_size) ?
                    edit_dis < config_.max_dist * (int)len_sum / config_.min_danmu_size:
                    edit_dis <= config_.max_dist
            ) {
                return sim_result(combined_edit_distance, edit_dis, idx_delta);
            }
        }

        bool calc_py_dis = config_.use_pinyin
            && std::abs(p.pinyin.length - q.pinyin.length) <= config_.max_dist;
        if(calc_py_dis) {
            int py_dis = edit_distance(
                p.pinyin,
                q.pinyin);
            if(
                (len_sum < (sim_uint)config_.min_danmu_size) ?
                    py_dis < config_.max_dist * (int)len_sum / config_.min_danmu_size:
                    py_dis <= config_.max_dist
            ) {
                return sim_result(combined_pinyin_distance, py_dis, idx_delta);
            }
        }

        bool calc_cosine_sim = config_.max_cosine <= 100 && !(
            calc_edit_dis && edit_dis >= (int)len_sum
        );
        if(calc_cosine_sim) {
            int cosine_sim = 100 * cosine_distance(
                p.gram,
                q.gram);
            if(cosine_sim >= config_.max_cosine) {
                return sim_result(combined_cosine_distance, cosine_sim, idx_delta);
            }
        }

        return 0;
    }

    // ──── 公开接口 ────
    void begin_chunk(sim_ushort* str_buf, int max_dist, int max_cosine,
                     bool use_pinyin, bool cross_mode) {
        config_.str_buf = str_buf;
        config_.max_dist = max_dist;
        config_.max_cosine = max_cosine;
        config_.use_pinyin = use_pinyin;
        config_.cross_mode = cross_mode;
        config_.min_danmu_size = std::max(1, max_dist * 2);
        config_.index_r_lock = false;
        config_.dispose_idx = 0;
        nearby_danmu_.clear();
        precise_matcher_.clear();
    }

    sim_uint check_similar(sim_uint mode, sim_uint index_l) {
        sim_uint index_r = static_cast<sim_uint>(nearby_danmu_.size());
        auto p = DanmuCacheline(this, config_.str_buf, mode, index_r);
        sim_ulong h = precise_matcher_hash(config_.str_buf,
                                           config_.cross_mode ? 0 : mode);

        for(; config_.dispose_idx < index_l; config_.dispose_idx++) {
            nearby_danmu_[config_.dispose_idx].dispose(this);
        }

        if(index_l + SIM_MAX_IDX_RANGE < index_r)
            index_l = index_r - SIM_MAX_IDX_RANGE;

        auto it = precise_matcher_.find(h);
        if(it != precise_matcher_.end()) {
            sim_uint idx = it->second;
            if(idx >= index_l && idx < index_r) {
                sim_uint res = check_similar_single(p, nearby_danmu_[idx]);
                if(res) {
                    res = (res & ((1u << 30) - 1u)) | (combined_identical << 30);
                    return res;
                }
            }
        }

        for(sim_uint idx = index_l; idx < index_r; idx++) {
            sim_uint res = check_similar_single(p, nearby_danmu_[idx]);
            if(res) {
                precise_matcher_[h] = idx;
                return res;
            }
        }

        if(!config_.index_r_lock) {
            precise_matcher_[h] = index_r;
            nearby_danmu_.push_back(std::move(p));
        }
        return 0;
    }

    void begin_index_lock() { config_.index_r_lock = true; }

    void force_insert(sim_uint mode) {
        if (!config_.str_buf) return;
        sim_uint index_r = static_cast<sim_uint>(nearby_danmu_.size());
        auto p = DanmuCacheline(this, config_.str_buf, mode, index_r);
        sim_ulong h = precise_matcher_hash(config_.str_buf,
                                           config_.cross_mode ? 0 : mode);
        precise_matcher_[h] = index_r;
        nearby_danmu_.push_back(std::move(p));
    }

    void reset() {
        nearby_danmu_.clear();
        precise_matcher_.clear();
        config_.dispose_idx = 0;
        config_.index_r_lock = false;
    }

    // ──── 数据成员（放在 DanmuCacheline 定义之后） ────
    std::vector<DanmuCacheline> nearby_danmu_;
    std::unordered_map<sim_ulong, sim_uint> precise_matcher_;
    std::unique_ptr<short[]> ed_a_;
    std::unique_ptr<short[]> ed_b_;
};

// ══════════════════════════════════════════════
// ──── 高级 API 数据结构 ────
// ══════════════════════════════════════════════

struct DanmakuSimItem {
    std::string text;
    int mode = 0;           // 0=scroll, 1=top, 2=bottom
    double time_seconds = 0.0;
};

struct SimConfig {
    int max_dist = 3;
    int max_cosine = 70;
    bool use_pinyin = true;
    bool cross_mode = false;
    double time_window = 45.0;
};

struct SimPair {
    int source_index = 0;
    int target_index = 0;
    std::string reason;     // "identical" / "edit_distance" / "pinyin_distance" / "cosine"
    int distance = 0;
    double score = 0.0;     // 0.0-1.0
};

struct SimResult {
    std::vector<SimPair> pairs;
    std::vector<std::vector<int>> groups;
};

// ══════════════════════════════════════════════
// ──── 高级 API 函数 ────
// ══════════════════════════════════════════════

/// 批量查重：对 N 条弹幕做全对比较，返回相似对和分组
SimResult danmaku_similarity_check(
    const std::vector<DanmakuSimItem>& items,
    const SimConfig& config);

/// 单对相似度：输入两段文本，返回 0.0-1.0 分数
double danmaku_pair_similarity(
    const std::string& text_a,
    const std::string& text_b,
    bool use_pinyin);

/// JSON 便捷接口：输入弹幕 JSON + 配置 JSON，返回结果 JSON
std::string similarity_check_batch_json(
    const std::string& items_json,
    const std::string& config_json);

} // namespace nipaplay::native
