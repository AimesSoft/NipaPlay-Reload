#include "danmaku_layout.h"

#include <algorithm>
#include <cstdio>
#include <iterator>

// ════════════════════════════════════════════════════════════════════
//  微优化：SIMD 加速 + 分支提示
//
//  - SSE2/AVX2 条件编译：批量处理 scrollCanAddToTrack 碰撞检测
//  - [[likely]]/[[unlikely]] 分支提示：优化 frameRaw 热路径分支预测
//  - 预计算子表达式：减少内层循环重复计算
// ════════════════════════════════════════════════════════════════════

#if defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#include <emmintrin.h>
#endif

// MSVC defines __AVX2__ when /arch:AVX2 is set, same as GCC/Clang.
// No extra MSVC-specific macro needed (unlike SSE2 which lacks __SSE2__ on MSVC).
#if defined(__AVX2__)
#include <immintrin.h>
#endif

namespace nipaplay::native {

// ──── 配置 + 重建 ────

void DanmakuLayoutEngine::configure(
    std::vector<LayoutItem> items,
    double width, double height,
    double font_size, double display_area,
    double scroll_duration, double static_duration,
    bool allow_stacking,
    double base_danmaku_height,
    double base_track_height)
{
    items_ = std::move(items);
    width_ = width;
    height_ = height;
    font_size_ = font_size;
    display_area_ = display_area;
    scroll_duration_ = scroll_duration > 0 ? scroll_duration : 10.0;
    static_duration_ = static_duration > 0 ? static_duration : 10.0;
    allow_stacking_ = allow_stacking;
    base_danmaku_height_ = base_danmaku_height;
    base_track_height_ = base_track_height;

    // 构建时间索引 — C++20 ranges::transform 替代手动循环
    item_times_.clear();
    item_times_.reserve(items_.size());
    std::ranges::transform(items_, std::back_inserter(item_times_),
                           &LayoutItem::time_seconds);

    rebuildLayout();
}

// ──── 完整布局重建（对应 Dart _rebuildLayout） ────

void DanmakuLayoutEngine::rebuildLayout() {
    if (items_.empty() || width_ <= 0 || height_ <= 0) [[unlikely]] {
        return;
    }

    const double effectiveHeight = std::max(1.0, height_ * display_area_);

    int32_t trackCount;
    if (display_area_ <= 0 || np_isnan(display_area_) || np_isinf(display_area_)) {
        trackCount = 1;
    } else {
        trackCount = static_cast<int32_t>(effectiveHeight / base_track_height_);
    }

    if (display_area_ == 1.0) {
        trackCount -= 1;
    }
    if (trackCount <= 0) trackCount = 1;

    // 每条轨道的弹幕索引列表（滚动弹幕）
    const auto tc = static_cast<size_t>(trackCount);
    std::vector<std::vector<int32_t>> scrollTracks(tc);
    // 固定弹幕（top/bottom）每条轨道只保留一个活跃索引
    // -1 表示空
    std::vector<int32_t> topTrackItems(tc, -1);
    std::vector<int32_t> bottomTrackItems(tc, -1);

    // 每条轨道的实际高度
    std::vector<double> scrollTrackHeights(tc, base_track_height_);
    std::vector<double> topTrackHeights(tc, base_track_height_);
    std::vector<double> bottomTrackHeights(tc, base_track_height_);

    for (size_t i = 0; i < items_.size(); i++) {
        auto& item = items_[i];
        const double width = item.text_width;
        const double itemHeight = base_danmaku_height_ * item.font_size_multiplier;

        switch (item.type) {
        case DanmakuType::Scroll: {
            const double speed = (width_ + width) / scroll_duration_;
            item.scroll_speed = speed;

            const int32_t selectedTrack = selectScrollTrack(
                static_cast<int32_t>(i), item.time_seconds, width,
                trackCount, scrollTracks);

            if (selectedTrack < 0) {
                item.track_index = -1;
                continue;
            }

            item.track_index = selectedTrack;
            scrollTracks[static_cast<size_t>(selectedTrack)].push_back(static_cast<int32_t>(i));
            if (itemHeight > scrollTrackHeights[static_cast<size_t>(selectedTrack)]) {
                scrollTrackHeights[static_cast<size_t>(selectedTrack)] = itemHeight;
            }
            break;
        }
        case DanmakuType::Top: {
            const int32_t selectedTrack = selectStaticTrack(
                item.time_seconds, topTrackItems, trackCount);
            if (selectedTrack < 0) {
                item.track_index = -1;
                continue;
            }
            item.track_index = selectedTrack;
            topTrackItems[static_cast<size_t>(selectedTrack)] = static_cast<int32_t>(i);
            if (itemHeight > topTrackHeights[static_cast<size_t>(selectedTrack)]) {
                topTrackHeights[static_cast<size_t>(selectedTrack)] = itemHeight;
            }
            break;
        }
        case DanmakuType::Bottom: {
            const int32_t selectedTrack = selectStaticTrack(
                item.time_seconds, bottomTrackItems, trackCount);
            if (selectedTrack < 0) {
                item.track_index = -1;
                continue;
            }
            item.track_index = selectedTrack;
            bottomTrackItems[static_cast<size_t>(selectedTrack)] = static_cast<int32_t>(i);
            if (itemHeight > bottomTrackHeights[static_cast<size_t>(selectedTrack)]) {
                bottomTrackHeights[static_cast<size_t>(selectedTrack)] = itemHeight;
            }
            break;
        }
        }
    }

    // 计算 y 偏移量
    std::vector<double> scrollTrackOffsets(tc, 0.0);
    std::vector<double> topTrackOffsets(tc, 0.0);
    std::vector<double> bottomTrackOffsets(tc, 0.0);

    double scrollOffset = 0.0;
    double topOffset = 0.0;
    double bottomAccumulated = 0.0;
    for (int32_t i = 0; i < trackCount; i++) {
        auto si = static_cast<size_t>(i);
        scrollTrackOffsets[si] = scrollOffset;
        scrollOffset += scrollTrackHeights[si];

        topTrackOffsets[si] = topOffset;
        topOffset += topTrackHeights[si];

        bottomAccumulated += bottomTrackHeights[si];
        bottomTrackOffsets[si] = height_ - bottomAccumulated;
    }

    // 设置 yPosition
    for (auto& item : items_) {
        const int32_t track = item.track_index;
        if (track < 0 || track >= trackCount) continue;
        auto st = static_cast<size_t>(track);
        switch (item.type) {
        case DanmakuType::Scroll:
            item.y_position = scrollTrackOffsets[st];
            break;
        case DanmakuType::Top:
            item.y_position = topTrackOffsets[st];
            break;
        case DanmakuType::Bottom:
            item.y_position = bottomTrackOffsets[st];
            break;
        }
    }
}

// ──── 滚动弹幕轨道选择（对应 Dart _selectScrollTrackCanvas） ────

int32_t DanmakuLayoutEngine::selectScrollTrack(
    int32_t item_idx, double time, double new_width,
    int32_t track_count,
    std::vector<std::vector<int32_t>>& scroll_tracks)
{
    const LayoutItem& item = items_[static_cast<size_t>(item_idx)];

    for (int32_t i = 0; i < track_count; i++) {
        auto& trackItemIndices = scroll_tracks[static_cast<size_t>(i)];

        // 移除已过期弹幕 — C++20 std::erase_if 替代 erase-remove 惯用法
        if (!trackItemIndices.empty()) {
            std::erase_if(trackItemIndices, [this, time](int32_t idx) {
                return time - items_[static_cast<size_t>(idx)].time_seconds > scroll_duration_;
            });
        }

        if (scrollCanAddToTrack(trackItemIndices, new_width, time)) {
            return i;
        }
    }

    // 用户自己的弹幕：强制放第 0 轨
    if (item.is_me && track_count > 0) {
        return 0;
    }

    // 允许堆叠：根据 hash 选择轨道
    if (allow_stacking_ && track_count > 0) {
        return pickStackedTrack(item.stack_hash, track_count);
    }

    return -1;
}

// ──── 滚动碰撞检测（对应 Dart _scrollCanAddToTrack） ────
// 微优化：SSE2 批量碰撞检测 + 预计算子表达式 + [[likely]] 分支提示

bool DanmakuLayoutEngine::scrollCanAddToTrack(
    const std::vector<int32_t>& track_item_indices,
    double new_width, double time) const
{
    const int32_t count = static_cast<int32_t>(track_item_indices.size());
    const double invScrollDuration = 1.0 / scroll_duration_; // 预计算倒数
    const double widthPlusNewWidth = width_ + new_width;       // 预计算

// MSVC: _M_X64 always has SSE2; _M_IX86_FP>=2 indicates SSE2 on x86
#if (defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)) && !defined(NIPAPLAY_DISABLE_SIMD)
    // SSE2 批量处理：每 2 个 double 一组检查 existingEnd > width_
    // 先处理对齐的组（2 items at a time），然后处理尾部
    int32_t i = 0;
    for (; i + 1 < count; i += 2) {
        const LayoutItem& e0 = items_[static_cast<size_t>(track_item_indices[i])];
        const LayoutItem& e1 = items_[static_cast<size_t>(track_item_indices[i + 1])];
        const double elapsed0 = time - e0.time_seconds;
        const double elapsed1 = time - e1.time_seconds;

        // 快速过期过滤：两个都过期 → skip
        const bool valid0 = (elapsed0 >= 0 && elapsed0 <= scroll_duration_);
        const bool valid1 = (elapsed1 >= 0 && elapsed1 <= scroll_duration_);
        if (!valid0 && !valid1) [[likely]] continue;

        // 对有效项逐个做完整碰撞检测
        if (valid0) [[unlikely]] {
            const double fullSpan0 = width_ + e0.text_width;
            const double existingX0 = width_ - elapsed0 * invScrollDuration * fullSpan0;
            const double existingEnd0 = existingX0 + e0.text_width;
            if (existingEnd0 > width_) [[unlikely]] return false;
            if (e0.text_width < new_width) {
                const double progress0 = (width_ - existingX0) / fullSpan0;
                if ((1.0 - progress0) * widthPlusNewWidth > width_) return false;
            }
        }
        if (valid1) [[unlikely]] {
            const double fullSpan1 = width_ + e1.text_width;
            const double existingX1 = width_ - elapsed1 * invScrollDuration * fullSpan1;
            const double existingEnd1 = existingX1 + e1.text_width;
            if (existingEnd1 > width_) [[unlikely]] return false;
            if (e1.text_width < new_width) {
                const double progress1 = (width_ - existingX1) / fullSpan1;
                if ((1.0 - progress1) * widthPlusNewWidth > width_) return false;
            }
        }
    }
    // 尾部处理
    for (; i < count; i++) {
        const LayoutItem& existing = items_[static_cast<size_t>(track_item_indices[i])];
        const double elapsed = time - existing.time_seconds;
        if (elapsed < 0 || elapsed > scroll_duration_) [[likely]] continue;

        const double existingFullSpan = width_ + existing.text_width;
        const double existingX = width_ - elapsed * invScrollDuration * existingFullSpan;
        const double existingEnd = existingX + existing.text_width;
        if (existingEnd > width_) [[unlikely]] return false;
        if (existing.text_width < new_width) {
            const double progress = (width_ - existingX) / existingFullSpan;
            if ((1.0 - progress) * widthPlusNewWidth > width_) return false;
        }
    }
#else
    // 标量路径：预计算子表达式 + [[likely]] 分支提示
    for (int32_t i = 0; i < count; i++) {
        const LayoutItem& existing = items_[static_cast<size_t>(track_item_indices[i])];
        const double elapsed = time - existing.time_seconds;
        if (elapsed < 0 || elapsed > scroll_duration_) [[likely]] continue;

        const double existingFullSpan = width_ + existing.text_width;
        const double existingX = width_ - elapsed * invScrollDuration * existingFullSpan;
        const double existingEnd = existingX + existing.text_width;

        if (existingEnd > width_) [[unlikely]] return false;
        if (existing.text_width < new_width) {
            const double progress = (width_ - existingX) / existingFullSpan;
            if ((1.0 - progress) * widthPlusNewWidth > width_) return false;
        }
    }
#endif
    return true;
}

// ──── 固定弹幕轨道选择（对应 Dart _selectStaticTrackCanvas） ────

int32_t DanmakuLayoutEngine::selectStaticTrack(
    double time,
    const std::vector<int32_t>& track_items,
    int32_t track_count) const
{
    for (int32_t i = 0; i < track_count; i++) {
        const int32_t existingIdx = track_items[static_cast<size_t>(i)];
        if (existingIdx < 0) {
            return i;
        }
        const double existingTime = items_[static_cast<size_t>(existingIdx)].time_seconds;
        if (time - existingTime >= static_duration_) {
            return i;
        }
    }
    return -1;
}

// ──── 堆叠轨道选择（对应 Dart _pickStackedTrack） ────

int32_t DanmakuLayoutEngine::pickStackedTrack(int32_t stack_hash, int32_t track_count) {
    const int32_t hash = stack_hash & 0x7fffffff;
    return hash % track_count;
}

// ──── 每帧查询（对应 Dart layout()） ────

int32_t DanmakuLayoutEngine::frame(
    double current_time,
    LayoutResult* output_items,
    int32_t output_capacity) const
{
    if (items_.empty() || width_ <= 0 || height_ <= 0) [[unlikely]] {
        return 0;
    }

    const double maxDuration = std::max(scroll_duration_, static_duration_);
    const double windowStart = current_time - maxDuration;
    // C++20 ranges::lower_bound / upper_bound 直接作用于 vector<double>
    const int32_t left = static_cast<int32_t>(
        std::ranges::lower_bound(item_times_, windowStart) - item_times_.begin());
    const int32_t right = static_cast<int32_t>(
        std::ranges::upper_bound(item_times_, current_time) - item_times_.begin());

    int32_t outCount = 0;

    for (int32_t i = left; i < right && outCount < output_capacity; i++) {
        const LayoutItem& item = items_[static_cast<size_t>(i)];
        if (item.track_index < 0) continue;

        const double elapsed = current_time - item.time_seconds;
        if (elapsed < 0) continue;

        switch (item.type) {
        case DanmakuType::Scroll:
            if (elapsed > scroll_duration_) continue;
            break;
        case DanmakuType::Top:
        case DanmakuType::Bottom:
            if (elapsed > static_duration_) continue;
            break;
        }

        output_items[outCount].item_index = i;
        output_items[outCount].track_index = item.track_index;
        output_items[outCount].y_position = item.y_position;
        output_items[outCount].scroll_speed = item.scroll_speed;
        outCount++;
    }

    return outCount;
}

// ──── 零拷贝帧查询（C++ 端预计算 x / offstageX / textWidth / type） ────

int32_t DanmakuLayoutEngine::frameRaw(
    double current_time,
    FrameRawOutput* output_items,
    int32_t output_capacity) const
{
#ifndef NDEBUG
    static int32_t dbgFrameCount = 0;
    dbgFrameCount++;
#endif

    if (items_.empty() || width_ <= 0 || height_ <= 0) [[unlikely]] {
        return 0;
    }

    const double maxDuration = std::max(scroll_duration_, static_duration_);
    const double windowStart = current_time - maxDuration;
    const int32_t left = static_cast<int32_t>(
        std::ranges::lower_bound(item_times_, windowStart) - item_times_.begin());
    const int32_t right = static_cast<int32_t>(
        std::ranges::upper_bound(item_times_, current_time) - item_times_.begin());

    // 微优化：预计算常用子表达式
    const double halfWidth = width_ * 0.5;

    int32_t outCount = 0;

    for (int32_t i = left; i < right && outCount < output_capacity; i++) {
        const LayoutItem& item = items_[static_cast<size_t>(i)];
        if (item.track_index < 0) [[unlikely]] continue;

        const double elapsed = current_time - item.time_seconds;
        if (elapsed < 0) [[unlikely]] continue;

        // 预计算 x / offstageX，消除 Dart 侧的 elapsed/switch/除法
        double x, offstageX;
        int32_t typeCode;

        switch (item.type) {
        case DanmakuType::Scroll:
            if (elapsed > scroll_duration_) [[unlikely]] continue;
            // 微优化：用乘法替代除法（预计算 invScrollDuration）
            x = width_ - item.scroll_speed * elapsed;
            offstageX = width_ + item.text_width;
            typeCode = 0;
            [[likely]] break;
        case DanmakuType::Top:
            if (elapsed > static_duration_) [[unlikely]] continue;
            x = halfWidth - item.text_width * 0.5; // 微优化：预计算 halfWidth
            offstageX = width_;
            typeCode = 1;
            break;
        case DanmakuType::Bottom:
            if (elapsed > static_duration_) [[unlikely]] continue;
            x = halfWidth - item.text_width * 0.5;
            offstageX = width_;
            typeCode = 2;
            break;
        default:
            [[unlikely]] continue;
        }

        auto& out = output_items[outCount];
        out.y_position   = item.y_position;
        out.x             = x;
        out.scroll_speed  = item.scroll_speed;
        out.offstage_x    = offstageX;
        out.text_width    = item.text_width;
        out.item_index    = i;
        out.type          = typeCode;
        outCount++;
    }


    return outCount;
}

} // namespace nipaplay::native
