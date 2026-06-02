#include "danmaku_layout.h"

#include <algorithm>

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

    // 构建时间索引
    item_times_.clear();
    item_times_.reserve(items_.size());
    for (const auto& item : items_) {
        item_times_.push_back(item.time_seconds);
    }

    rebuildLayout();
}

// ──── 完整布局重建（对应 Dart _rebuildLayout） ────

void DanmakuLayoutEngine::rebuildLayout() {
    if (items_.empty() || width_ <= 0 || height_ <= 0) {
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

        // 移除已过期弹幕
        if (!trackItemIndices.empty()) {
            auto eraseFrom = std::remove_if(
                trackItemIndices.begin(), trackItemIndices.end(),
                [this, time](int32_t idx) {
                    return time - items_[static_cast<size_t>(idx)].time_seconds > scroll_duration_;
                });
            trackItemIndices.erase(eraseFrom, trackItemIndices.end());
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

bool DanmakuLayoutEngine::scrollCanAddToTrack(
    const std::vector<int32_t>& track_item_indices,
    double new_width, double time) const
{
    for (int32_t idx : track_item_indices) {
        const LayoutItem& existing = items_[static_cast<size_t>(idx)];
        const double elapsed = time - existing.time_seconds;
        if (elapsed < 0 || elapsed > scroll_duration_) {
            continue;
        }

        const double existingX = width_ -
            (elapsed / scroll_duration_) * (width_ + existing.text_width);
        const double existingEnd = existingX + existing.text_width;

        if (width_ - existingEnd < 0) {
            return false;
        }
        if (existing.text_width < new_width) {
            const double progress =
                (width_ - existingX) / (existing.text_width + width_);
            if ((1.0 - progress) > (width_ / (width_ + new_width))) {
                return false;
            }
        }
    }
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
    if (items_.empty() || width_ <= 0 || height_ <= 0) {
        return 0;
    }

    const double maxDuration = std::max(scroll_duration_, static_duration_);
    const double windowStart = current_time - maxDuration;
    const int32_t left = lowerBound(windowStart);
    const int32_t right = upperBound(current_time);

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

// ──── 二分查找工具 ────

int32_t DanmakuLayoutEngine::lowerBound(double value) const {
    int32_t lo = 0;
    int32_t hi = static_cast<int32_t>(item_times_.size());
    while (lo < hi) {
        const int32_t mid = (lo + hi) >> 1;
        if (item_times_[static_cast<size_t>(mid)] < value) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

int32_t DanmakuLayoutEngine::upperBound(double value) const {
    int32_t lo = 0;
    int32_t hi = static_cast<int32_t>(item_times_.size());
    while (lo < hi) {
        const int32_t mid = (lo + hi) >> 1;
        if (item_times_[static_cast<size_t>(mid)] <= value) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

} // namespace nipaplay::native
