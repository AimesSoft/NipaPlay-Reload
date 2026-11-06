// Copyright (c) Aimes Soft and contributors.
// SPDX-License-Identifier: MIT
#pragma once
#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <thread>
#include <type_traits>
#include <utility>

namespace erika_flutter {
// FIFO commands and at most one queued OR executing frame. Native clocks are
// optional; Windows continues to use its external waitable timer unchanged.
// Tasks/finalizers must contain exceptions and never wait for UI completions:
// the platform is allowed to join this owner at a surface lifetime fence.
class ErikaPresenterWorker {
 public:
  using Task = std::function<void()>;
  ErikaPresenterWorker() : thread_([this] { Run(); }) {}
  ~ErikaPresenterWorker() { Stop(); }
  ErikaPresenterWorker(const ErikaPresenterWorker&) = delete;
  ErikaPresenterWorker& operator=(const ErikaPresenterWorker&) = delete;
  bool Post(Task task) { return Enqueue(std::move(task), false, {}); }
  bool RequestFrame(Task task, Task cancelled = {}) {
    return Enqueue(std::move(task), true, std::move(cancelled));
  }
  // A monotonic clock on the owner, with no queued timer callbacks. Slow frames
  // skip expired deadlines. Commands still run FIFO between frames.
  void SetFrameTask(Task task, std::chrono::milliseconds period = std::chrono::milliseconds(16)) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (stopping_) return;
      frame_task_ = std::move(task);
      period_ = period;
      deadline_ = std::chrono::steady_clock::now() + period_;
    }
    ready_.notify_one();
  }
  // For legacy synchronous host APIs and surface destruction fences only.
  // Callers serialize Call/Stop; never call this from the owner itself.
  template<class F> auto Call(F task) -> decltype(task()) {
    using R = decltype(task());
    auto done = std::make_shared<std::promise<R>>();
    auto result = done->get_future();
    if (!Post([done, task = std::move(task)]() mutable {
      if constexpr (std::is_void_v<R>) { task(); done->set_value(); }
      else done->set_value(task());
    })) std::terminate();
    return result.get();
  }
  // The optional waiter services OS sent messages for Windows DXGI HWND work.
  // It must not dispatch posted Flutter/plugin method calls.
  void Stop(Task finalizer = {}, std::function<void(std::thread&)> waiter = {}) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!stopping_) {
        stopping_ = true;
        frame_task_ = {};
        for (auto it = tasks_.begin(); it != tasks_.end();) {
          if (it->frame) {
            if (it->cancelled) {
              it->task = std::move(it->cancelled); it->frame = false; ++it;
            } else it = tasks_.erase(it);
          } else ++it;
        }
        if (finalizer) tasks_.push_back({std::move(finalizer), false, {}});
      }
    }
    ready_.notify_one();
    if (thread_.joinable()) {
      if (waiter) waiter(thread_);
      thread_.join();
    }
  }
 private:
  struct Entry { Task task; bool frame; Task cancelled; };
  bool Enqueue(Task task, bool frame, Task cancelled) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (stopping_ || (frame && frame_pending_)) return false;
      if (frame) frame_pending_ = true;
      tasks_.push_back({std::move(task), frame, std::move(cancelled)});
    }
    ready_.notify_one();
    return true;
  }
  void Run() {
    for (;;) {
      Entry entry;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        for (;;) {
          if (!tasks_.empty()) {
            entry = std::move(tasks_.front()); tasks_.pop_front(); break;
          }
          if (stopping_) return;
          if (!frame_task_) { ready_.wait(lock); continue; }
          if (std::chrono::steady_clock::now() < deadline_) {
            ready_.wait_until(lock, deadline_); continue;
          }
          entry = {frame_task_, true, {}};
          frame_pending_ = true;
          break;
        }
      }
      entry.task();
      if (entry.frame) {
        std::lock_guard<std::mutex> lock(mutex_);
        frame_pending_ = false;
        const auto now = std::chrono::steady_clock::now();
        if (frame_task_ && deadline_ <= now)
          deadline_ += period_ * ((now - deadline_) / period_ + 1);
      }
    }
  }
  std::mutex mutex_;
  std::condition_variable ready_;
  std::deque<Entry> tasks_;
  Task frame_task_;
  std::chrono::milliseconds period_{16};
  std::chrono::steady_clock::time_point deadline_{};
  bool stopping_ = false, frame_pending_ = false;
  std::thread thread_; // Last: all state exists before Run starts.
};
} // namespace erika_flutter

namespace erika { using PresenterWorker = erika_flutter::ErikaPresenterWorker; }
