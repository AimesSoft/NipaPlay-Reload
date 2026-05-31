#include "similarity_engine.h"
#include <unordered_map>
#include <vector>
#include <cmath>
#include <algorithm>
#include <cstring>
#include <memory>
#include <new>

// pinyin_dict 改为懒加载，避免 DLL 加载时在 loader lock 下初始化大型 map
extern const std::unordered_map<ushort, std::pair<uchar, uchar>>& get_pinyin_dict();

constexpr int PINYIN_BASE = 0xe000;
constexpr int HASH_MOD = 1007;
constexpr int MAX_HASH_VAL = std::max(HASH_MOD * HASH_MOD, 1 << 16) + 7;

class SimilarityEngine {
    // ===== 原全局可变状态 → 实例成员 =====
    struct Config {
        int max_dist = 0;
        int max_cosine = 0;
        bool use_pinyin = false;
        bool cross_mode = false;
        ushort* str_buf = nullptr;
        bool index_r_lock = false;
        int min_danmu_size = 0;
        uint dispose_idx = 0;
    } config_;

    // 数据成员声明移至类底部（MSVC 要求完整类型才能实例化 vector）
    // 此处仅前向声明，实际定义在 DanmuCacheline 之后

public:
    SimilarityEngine();   // 构造函数声明，定义在类底部
    ~SimilarityEngine() = default;
    SimilarityEngine(const SimilarityEngine&) = delete;
    SimilarityEngine& operator=(const SimilarityEngine&) = delete;

    // --- UnorderedContainer ---
    // 原代码中 UnorderedContainer::push/cleanup 使用全局 ed_a[]
    // 实例化后：UnorderedContainer 持有 ed_a 指针，通过指针访问
    template<typename T>
    struct UnorderedContainer {
        std::vector<std::pair<T, ushort>> data{};
        int length{};
        short* ed_a;  // 指向引擎实例的 scratch buffer

        UnorderedContainer(short* ea): length(0), ed_a(ea) {}

        // push: 与原代码完全一致，仅 ed_a → this->ed_a
        void push(T x) {
            length++;
            if(ed_a[x] == 0) {
                data.emplace_back(x, 1);
                ed_a[x] = static_cast<short>(data.size());
            } else {
                data[ed_a[x]-1].second++;
            }
        }
        // cleanup: 与原代码完全一致
        void cleanup() {
            for(auto& p: data) {
                ed_a[p.first] = 0;
            }
        }
        // dispose: 与原代码完全一致
        void dispose() {
            data.clear();
        }
    };

    // --- DanmuCacheline ---
    // 原代码: explicit DanmuCacheline(const ushort *s, uint mode, uint idx)
    //   直接访问全局 config, pinyin_dict, ed_a
    // 实例化: 增加一个 SimilarityEngine* engine 参数
    //   通过 engine->config_ 访问配置，pinyin_dict 仍全局
    //   UnorderedContainer 的 scratch buffer 通过 engine->ed_a_.get() 获取
    struct DanmuCacheline {
        uint idx{};
        uint mode{};
        std::vector<ushort> orig{};
        UnorderedContainer<ushort> str;
        UnorderedContainer<ushort> pinyin;
        UnorderedContainer<uint> gram;
        std::vector<ulong> peers{};

        // 关键设计：传入引擎指针访问实例成员
        explicit DanmuCacheline(SimilarityEngine* engine,
                               const ushort* s, uint mode, uint idx)
            : idx(idx), mode(mode)
            , str(engine->ed_a_.get())      // str 使用 ed_a scratch buffer
            , pinyin(engine->ed_a_.get())   // pinyin 使用 ed_a（互斥使用）
            , gram(engine->ed_a_.get())     // gram 使用 ed_a（key 空间不同，互斥使用）
            , peers({})
        {
            // gen orig and str
            // 与原代码完全一致
            for(ushort c = *s; c; c = *(++s)) {
                orig.push_back(c);
                str.push(c);
            }
            str.cleanup();

            // gen pinyin
            // 原代码: if(config.use_pinyin)
            // 替换:   if(engine->config_.use_pinyin)
            if(engine->config_.use_pinyin) {
                const auto& pd = get_pinyin_dict();
                for(ushort c: orig) {
                    auto cs = pd.find(c);
                    if(cs != pd.end()) {
                        pinyin.push(PINYIN_BASE + cs->second.first);
                        if(cs->second.second)
                            pinyin.push(PINYIN_BASE + cs->second.second);
                    } else {
                        if(c >= 'A' && c <= 'Z') c += 'a' - 'A';
                        pinyin.push(c);
                    }
                }
                pinyin.cleanup();
            }

            // gen gram
            // 原代码: if(config.max_cosine<=100 && !orig.empty())
            // 替换:   if(engine->config_.max_cosine<=100 && !orig.empty())
            if(engine->config_.max_cosine <= 100 && !orig.empty()) {
                uint clast = (*orig.crbegin()) % HASH_MOD;
                for(uint c: orig) {
                    c = c % HASH_MOD;
                    gram.push(clast * HASH_MOD + c);
                    clast = c;
                }
                gram.cleanup();
            }
        }

        // dispose: 原代码访问全局 precise_matcher
        // 替换: 传入 engine 指针访问 engine->precise_matcher_
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

    // --- precise_matcher_hash ---
    // 与原代码完全一致，无全局状态依赖
    ulong precise_matcher_hash(const ushort* s, ushort mode) {
        ulong ret = mode;
        for(ushort c = *s; c; c = *(++s)) {
            ret ^= c + 0x9e3779b9 + (ret << 6) + (ret >> 2);
        }
        return ret;
    }

    // --- edit_distance ---
    // 原代码使用全局 ed_a[]
    // 替换: ed_a → ed_a_.get()
    int edit_distance(UnorderedContainer<ushort>& p,
                      UnorderedContainer<ushort>& q) {
        short* ea = ed_a_.get();
        for(auto& item: p.data) ea[item.first] += item.second;
        for(auto& item: q.data) ea[item.first] -= item.second;
        int ans = 0;
        for(auto& item: p.data) { ans += std::abs(ea[item.first]); ea[item.first] = 0; }
        for(auto& item: q.data) { ans += std::abs(ea[item.first]); ea[item.first] = 0; }
        return ans;
    }

    // --- cosine_distance ---
    // 原代码使用全局 ed_a[], ed_b[]
    // 替换: ed_a → ed_a_.get(), ed_b → ed_b_.get()
    float cosine_distance(UnorderedContainer<uint>& p,
                          UnorderedContainer<uint>& q) {
        short* ea = ed_a_.get();
        short* eb = ed_b_.get();
        for(auto& item: p.data) ea[item.first] += item.second;
        for(auto& item: q.data) eb[item.first] += item.second;
        int x=0, y=0, z=0;
        for(auto& item: p.data) {
            int xa = ea[item.first], xb = eb[item.first];
            x += xa*xb; y += xa*xa; z += xb*xb;
            ea[item.first] = 0; eb[item.first] = 0;
        }
        for(auto& item: q.data) {
            int xb = eb[item.first]; z += xb*xb; eb[item.first] = 0;
        }
        if(y<=0 || z<=0) return 0.0f;
        return static_cast<float>(x) * x / y / z;
    }

    // --- CombinedReason enum ---
    // 与原代码完全一致
    enum CombinedReason : uint {
        combined_identical = 0,
        combined_edit_distance = 1,
        combined_pinyin_distance = 2,
        combined_cosine_distance = 3,
    };

    constexpr static uint MAX_IDX_RANGE = (1<<19) - 3;
    constexpr static uint MAX_DIST_VAL = (1<<11) - 3;

    // --- sim_result ---
    // 与原代码完全一致
    static uint sim_result(CombinedReason reason, uint dist, uint target_idx) {
        return (reason << 30) | (std::min(dist, MAX_DIST_VAL) << 19) | target_idx;
    }

    // --- check_similar_single ---
    // 原代码: if(!config.cross_mode && p.mode!=q.mode)
    // 替换:   if(!config_.cross_mode && p.mode!=q.mode)
    uint check_similar_single(const DanmuCacheline& p,
                              const DanmuCacheline& q) {
        if(!config_.cross_mode && p.mode != q.mode)
            return 0;

        uint idx_delta = p.idx - q.idx;
        uint len_p = p.orig.size(), len_q = q.orig.size();
        uint len_sum = len_p + len_q;

        // check identical
        if(p.orig == q.orig)
            return sim_result(combined_identical, 0, idx_delta);

        // check edit dist
        int edit_dis = 0;
        bool calc_edit_dis = std::abs(p.str.length - q.str.length) <= config_.max_dist;
        if(calc_edit_dis) {
            edit_dis = edit_distance(
                const_cast<UnorderedContainer<ushort>&>(p.str),
                const_cast<UnorderedContainer<ushort>&>(q.str));
            if(
                (len_sum < (uint)config_.min_danmu_size) ?
                    edit_dis < config_.max_dist * (int)len_sum / config_.min_danmu_size:
                    edit_dis <= config_.max_dist
            ) {
                return sim_result(combined_edit_distance, edit_dis, idx_delta);
            }
        }

        // check pinyin dist
        bool calc_py_dis = config_.use_pinyin
            && std::abs(p.pinyin.length - q.pinyin.length) <= config_.max_dist;
        if(calc_py_dis) {
            int py_dis = edit_distance(
                const_cast<UnorderedContainer<ushort>&>(p.pinyin),
                const_cast<UnorderedContainer<ushort>&>(q.pinyin));
            if(
                (len_sum < (uint)config_.min_danmu_size) ?
                    py_dis < config_.max_dist * (int)len_sum / config_.min_danmu_size:
                    py_dis <= config_.max_dist
            ) {
                return sim_result(combined_pinyin_distance, py_dis, idx_delta);
            }
        }

        // check cosine similarity
        bool calc_cosine_sim = config_.max_cosine <= 100 && !(
            calc_edit_dis && edit_dis >= (int)len_sum
        );
        if(calc_cosine_sim) {
            int cosine_sim = 100 * cosine_distance(
                const_cast<UnorderedContainer<uint>&>(p.gram),
                const_cast<UnorderedContainer<uint>&>(q.gram));
            if(cosine_sim >= config_.max_cosine) {
                return sim_result(combined_cosine_distance, cosine_sim, idx_delta);
            }
        }

        return 0;
    }

    // ===== 公开接口 =====

    // --- begin_chunk ---
    void begin_chunk(ushort* str_buf, int max_dist, int max_cosine,
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

    // --- check_similar ---
    uint check_similar(uint mode, uint index_l) {
        uint index_r = static_cast<uint>(nearby_danmu_.size());
        auto p = DanmuCacheline(this, config_.str_buf, mode, index_r);
        ulong h = precise_matcher_hash(config_.str_buf,
                                       config_.cross_mode ? 0 : mode);

        for(; config_.dispose_idx < index_l; config_.dispose_idx++) {
            nearby_danmu_[config_.dispose_idx].dispose(this);
        }

        if(index_l + MAX_IDX_RANGE < index_r)
            index_l = index_r - MAX_IDX_RANGE;

        auto it = precise_matcher_.find(h);
        if(it != precise_matcher_.end()) {
            uint idx = it->second;
            if(idx >= index_l && idx < index_r) {
                uint res = check_similar_single(p, nearby_danmu_[idx]);
                if(res) {
                    res = (res & ((1u << 30) - 1u)) | (combined_identical << 30);
                    return res;
                }
            }
        }

        for(uint idx = index_l; idx < index_r; idx++) {
            uint res = check_similar_single(p, nearby_danmu_[idx]);
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

    // --- force_insert ---
    // 将当前 str_buf 中的内容作为新条目强制插入 nearby_danmu_，
    // 更新 precise_matcher_ 哈希表（覆盖过期条目）。
    // 调用前提：str_buf 中已写入了弹幕文本（UTF-16 + null terminator），
    // 且刚刚调用了 check_similar() 返回了匹配（被 Rust 拒绝）。
    // 此时 check_similar 没有将弹幕推入 nearby_danmu_（因为匹配成功不推入），
    // force_insert 补偿这一行为，让被拒绝的弹幕成为新的组代表。
    void force_insert(uint mode) {
        uint index_r = static_cast<uint>(nearby_danmu_.size());
        auto p = DanmuCacheline(this, config_.str_buf, mode, index_r);
        ulong h = precise_matcher_hash(config_.str_buf,
                                       config_.cross_mode ? 0 : mode);
        // 覆盖 precise_matcher_ 中的过期条目（如果有）
        precise_matcher_[h] = index_r;
        nearby_danmu_.push_back(std::move(p));
    }

    void reset() {
        nearby_danmu_.clear();
        precise_matcher_.clear();
        config_.dispose_idx = 0;
        config_.index_r_lock = false;
    }

    // ===== 数据成员（放在 DanmuCacheline 定义之后，MSVC 需要完整类型）=====
    std::vector<DanmuCacheline> nearby_danmu_;
    std::unordered_map<ulong, uint> precise_matcher_;
    std::unique_ptr<short[]> ed_a_;
    std::unique_ptr<short[]> ed_b_;
};

// 构造函数定义（类外定义，因为成员声明在类底部）
SimilarityEngine::SimilarityEngine()
    : ed_a_(std::make_unique<short[]>(MAX_HASH_VAL))
    , ed_b_(std::make_unique<short[]>(MAX_HASH_VAL))
{
    std::memset(ed_a_.get(), 0, MAX_HASH_VAL * sizeof(short));
    std::memset(ed_b_.get(), 0, MAX_HASH_VAL * sizeof(short));
}

// ===== C API 实现（所有函数均带 try-catch 和 null 检查，防止 C++ 异常穿透 FFI 边界导致进程崩溃） =====
extern "C" {
    SimilarityEngine* sim_engine_create() {
        try {
            return new (std::nothrow) SimilarityEngine();
        } catch (...) {
            return nullptr;
        }
    }
    void sim_engine_destroy(SimilarityEngine* engine) {
        try {
            if (engine) delete engine;
        } catch (...) {}
    }
    void sim_engine_begin_chunk(SimilarityEngine* engine,
        ushort* str_buf, int max_dist, int max_cosine,
        int use_pinyin, int cross_mode) {
        try {
            if (engine && str_buf) engine->begin_chunk(str_buf, max_dist, max_cosine,
                                use_pinyin != 0, cross_mode != 0);
        } catch (...) {}
    }
    uint sim_engine_check_similar(SimilarityEngine* engine,
        uint mode, uint index_l) {
        try {
            if (engine) return engine->check_similar(mode, index_l);
        } catch (...) {}
        return 0;
    }
    void sim_engine_begin_index_lock(SimilarityEngine* engine) {
        try {
            if (engine) engine->begin_index_lock();
        } catch (...) {}
    }
    void sim_engine_force_insert(SimilarityEngine* engine, uint mode) {
        try {
            if (engine && engine->config_.str_buf) engine->force_insert(mode);
        } catch (...) {}
    }
    void sim_engine_reset(SimilarityEngine* engine) {
        try {
            if (engine) engine->reset();
        } catch (...) {}
    }
}
