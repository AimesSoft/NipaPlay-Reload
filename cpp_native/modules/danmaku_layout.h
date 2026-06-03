#pragma once
#include <cstdint>
#include <bit>
#include <vector>

namespace nipaplay::native {

// ──── -ffast-math-safe NaN / Inf checks via bit inspection ────
// std::isnan / std::isinf are undefined under -ffast-math (-ffinite-math-only).
// C++20 std::bit_cast replaces memcpy-based type punning with a well-defined operation.
constexpr bool np_isnan(double v) noexcept {
    const auto bits = std::bit_cast<uint64_t>(v);
    // NaN: exponent all-1s (bits 52..62), mantissa non-zero (bits 0..51)
    return ((bits >> 52) & 0x7FFu) == 0x7FFu && (bits & 0x000FFFFFFFFFFFFFull) != 0;
}

constexpr bool np_isinf(double v) noexcept {
    const auto bits = std::bit_cast<uint64_t>(v);
    // Inf: exponent all-1s, mantissa zero
    return ((bits >> 52) & 0x7FFu) == 0x7FFu && (bits & 0x000FFFFFFFFFFFFFull) == 0;
}


/// 弹幕类型
enum class DanmakuType : int32_t {
    Scroll = 0,
    Top = 1,
    Bottom = 2,
};

/// 内部布局条目 — 仅存储布局相关字段
struct LayoutItem {
    double time_seconds = 0.0;
    DanmakuType type = DanmakuType::Scroll;
    double text_width = 0.0;
    double font_size_multiplier = 1.0;
    bool is_me = false;
    int32_t stack_hash = 0;

    // 布局结果（由 rebuildLayout 设置）
    int32_t track_index = -1;
    double y_position = 0.0;
    double scroll_speed = 0.0;
};

/// 布局结果输出（字段顺序与 NpLayoutResult 一致，确保 FFI 零拷贝直写）
struct LayoutResult {
    double y_position = 0.0;
    double scroll_speed = 0.0;
    int32_t item_index = -1;
    int32_t track_index = -1;
};

/// 弹幕布局引擎 — C++20 实现
/// 负责轨道分配、碰撞检测、yPosition 计算、时间窗口查询。
/// 文本测量由 Dart 侧（TextPainter）完成，结果作为 text_width 传入。
class DanmakuLayoutEngine {
public:
    DanmakuLayoutEngine() = default;
    ~DanmakuLayoutEngine() = default;

    DanmakuLayoutEngine(const DanmakuLayoutEngine&) = delete;
    DanmakuLayoutEngine& operator=(const DanmakuLayoutEngine&) = delete;
    DanmakuLayoutEngine(DanmakuLayoutEngine&&) = default;
    DanmakuLayoutEngine& operator=(DanmakuLayoutEngine&&) = default;

    /// 配置引擎：传入已排序的弹幕条目 + 参数，触发完整布局重建。
    /// text_width 由 Dart 侧 TextPainter 预测量。
    void configure(
        std::vector<LayoutItem> items,
        double width, double height,
        double font_size, double display_area,
        double scroll_duration, double static_duration,
        bool allow_stacking,
        double base_danmaku_height,
        double base_track_height);

    /// 每帧调用：获取指定时刻的活跃弹幕布局结果。
    /// 结果写入 output_items，返回实际数量。
    [[nodiscard]] int32_t frame(
        double current_time,
        LayoutResult* output_items,
        int32_t output_capacity) const;

    /// 获取已配置的弹幕条目数
    [[nodiscard]] int32_t itemCount() const {
        return static_cast<int32_t>(items_.size());
    }

private:
    void rebuildLayout();

    [[nodiscard]] int32_t selectScrollTrack(
        int32_t item_idx, double time, double new_width,
        int32_t track_count,
        std::vector<std::vector<int32_t>>& scroll_tracks);

    [[nodiscard]] bool scrollCanAddToTrack(
        const std::vector<int32_t>& track_item_indices,
        double new_width, double time) const;

    [[nodiscard]] int32_t selectStaticTrack(
        double time,
        const std::vector<int32_t>& track_items,
        int32_t track_count) const;

    [[nodiscard]] static int32_t pickStackedTrack(int32_t stack_hash, int32_t track_count);

    // 配置参数
    double width_ = 0.0;
    double height_ = 0.0;
    double font_size_ = 0.0;
    double display_area_ = 1.0;
    double scroll_duration_ = 10.0;
    double static_duration_ = 10.0;
    bool allow_stacking_ = false;
    double base_danmaku_height_ = 0.0;
    double base_track_height_ = 0.0;

    // 弹幕条目（按时间排序）
    std::vector<LayoutItem> items_;
    std::vector<double> item_times_;
};

} // namespace nipaplay::native
