use std::sync::atomic::{AtomicBool as CompletionAtomicBool, AtomicU64 as CompletionAtomicU64};
use std::sync::{Arc as CompletionArc, Condvar, Mutex as CompletionMutex};

/// A level-triggered completion state. Submitting a newer frame never erases
/// an older completion that the platform texture consumer has not observed.
pub(crate) struct FrameCompletionState {
    generation: CompletionAtomicU64,
    next_sequence: CompletionAtomicU64,
    completed_sequence: CompletionAtomicU64,
    consumed_sequence: CompletionAtomicU64,
    closed: CompletionAtomicBool,
    #[cfg(target_os = "windows")]
    ready_event: CompletionMutex<Option<CompletionArc<WindowsEventHandle>>>,
}

impl FrameCompletionState {
    pub(crate) fn new() -> Self {
        Self {
            generation: CompletionAtomicU64::new(1),
            next_sequence: CompletionAtomicU64::new(0),
            completed_sequence: CompletionAtomicU64::new(0),
            consumed_sequence: CompletionAtomicU64::new(0),
            closed: CompletionAtomicBool::new(false),
            #[cfg(target_os = "windows")]
            ready_event: CompletionMutex::new(None),
        }
    }

    pub(crate) fn begin_generation(&self) {
        self.generation.fetch_add(1, Ordering::AcqRel);
        let latest = self.next_sequence.load(Ordering::Acquire);
        self.completed_sequence.store(latest, Ordering::Release);
        self.consumed_sequence.store(latest, Ordering::Release);
    }

    pub(crate) fn register_submission(
        self: &CompletionArc<Self>,
        queue: &wgpu::Queue,
        driver: &GpuCompletionDriver,
    ) {
        if self.closed.load(Ordering::Acquire) {
            return;
        }
        let generation = self.generation.load(Ordering::Acquire);
        let sequence = self.next_sequence.fetch_add(1, Ordering::AcqRel) + 1;
        let state = CompletionArc::clone(self);
        queue.on_submitted_work_done(move || {
            if state.closed.load(Ordering::Acquire)
                || state.generation.load(Ordering::Acquire) != generation
            {
                return;
            }
            state.completed_sequence.fetch_max(sequence, Ordering::AcqRel);
            state.signal_platform_event();
        });
        driver.request_poll();
    }

    pub(crate) fn consume(&self) -> bool {
        loop {
            let completed = self.completed_sequence.load(Ordering::Acquire);
            let consumed = self.consumed_sequence.load(Ordering::Acquire);
            if completed <= consumed {
                return false;
            }
            if self
                .consumed_sequence
                .compare_exchange(consumed, completed, Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
            {
                return true;
            }
        }
    }

    pub(crate) fn close(&self) {
        self.closed.store(true, Ordering::Release);
        #[cfg(target_os = "windows")]
        if let Ok(mut event) = self.ready_event.lock() {
            *event = None;
        }
    }

    #[cfg(target_os = "windows")]
    pub(crate) fn bind_windows_event(&self, raw_event: usize) -> bool {
        let event = if raw_event == 0 {
            None
        } else {
            match WindowsEventHandle::duplicate(raw_event) {
                Some(event) => Some(CompletionArc::new(event)),
                None => return false,
            }
        };
        let has_pending = self.completed_sequence.load(Ordering::Acquire)
            > self.consumed_sequence.load(Ordering::Acquire);
        if let Ok(mut slot) = self.ready_event.lock() {
            *slot = event.clone();
        } else {
            return false;
        }
        if has_pending {
            if let Some(event) = event {
                event.signal();
            }
        }
        true
    }

    #[cfg(target_os = "windows")]
    fn signal_platform_event(&self) {
        let event = self.ready_event.lock().ok().and_then(|slot| slot.clone());
        if let Some(event) = event {
            event.signal();
        }
    }

    #[cfg(not(target_os = "windows"))]
    fn signal_platform_event(&self) {}
}

pub(crate) struct GpuCompletionDriver {
    wake: CompletionArc<(CompletionMutex<GpuCompletionWake>, Condvar)>,
}

struct GpuCompletionWake {
    requested: u64,
    closed: bool,
}

impl GpuCompletionDriver {
    pub(crate) fn start(device: CompletionArc<wgpu::Device>) -> Self {
        let wake = CompletionArc::new((
            CompletionMutex::new(GpuCompletionWake {
                requested: 0,
                closed: false,
            }),
            Condvar::new(),
        ));
        let worker_wake = CompletionArc::clone(&wake);
        let _ = thread::Builder::new()
            .name("next2-gpu-completion".to_string())
            .spawn(move || completion_worker(device, worker_wake));
        Self { wake }
    }

    pub(crate) fn request_poll(&self) {
        let (lock, condvar) = &*self.wake;
        if let Ok(mut state) = lock.lock() {
            state.requested = state.requested.wrapping_add(1);
            condvar.notify_one();
        }
    }
}

fn completion_worker(
    device: CompletionArc<wgpu::Device>,
    wake: CompletionArc<(CompletionMutex<GpuCompletionWake>, Condvar)>,
) {
    let (lock, condvar) = &*wake;
    let mut observed = 0u64;
    loop {
        let mut state = match lock.lock() {
            Ok(state) => state,
            Err(_) => return,
        };
        while !state.closed && state.requested == observed {
            state = match condvar.wait(state) {
                Ok(state) => state,
                Err(_) => return,
            };
        }
        if state.closed {
            return;
        }
        observed = state.requested;
        drop(state);

        let _ = device.poll(wgpu::PollType::Wait {
            submission_index: None,
            timeout: Some(Duration::from_millis(50)),
        });
    }
}

#[cfg(target_os = "windows")]
struct WindowsEventHandle(windows::Win32::Foundation::HANDLE);

#[cfg(target_os = "windows")]
unsafe impl Send for WindowsEventHandle {}
#[cfg(target_os = "windows")]
unsafe impl Sync for WindowsEventHandle {}

#[cfg(target_os = "windows")]
impl WindowsEventHandle {
    fn duplicate(raw_event: usize) -> Option<Self> {
        use windows::Win32::Foundation::{DuplicateHandle, HANDLE, DUPLICATE_SAME_ACCESS};
        use windows::Win32::System::Threading::GetCurrentProcess;
        let process = unsafe { GetCurrentProcess() };
        let mut duplicate = HANDLE::default();
        unsafe {
            DuplicateHandle(
                process,
                HANDLE(raw_event as *mut std::ffi::c_void),
                process,
                &mut duplicate,
                0,
                false,
                DUPLICATE_SAME_ACCESS,
            )
            .ok()?;
        }
        Some(Self(duplicate))
    }

    fn signal(&self) {
        let _ = unsafe { windows::Win32::System::Threading::SetEvent(self.0) };
    }
}

#[cfg(target_os = "windows")]
impl Drop for WindowsEventHandle {
    fn drop(&mut self) {
        let _ = unsafe { windows::Win32::Foundation::CloseHandle(self.0) };
    }
}

#[cfg(test)]
mod frame_completion_tests {
    use super::*;

    #[test]
    fn newer_submission_cannot_erase_unconsumed_completion() {
        let state = FrameCompletionState::new();
        state.completed_sequence.store(1, Ordering::Release);
        state.next_sequence.store(2, Ordering::Release);
        assert!(state.consume());
        assert!(!state.consume());
    }

    #[test]
    fn completions_coalesce_to_latest_sequence() {
        let state = FrameCompletionState::new();
        state.completed_sequence.store(8, Ordering::Release);
        assert!(state.consume());
        assert_eq!(state.consumed_sequence.load(Ordering::Acquire), 8);
        assert!(!state.consume());
    }

    #[test]
    fn generation_change_discards_previous_pending_state() {
        let state = FrameCompletionState::new();
        state.next_sequence.store(9, Ordering::Release);
        state.completed_sequence.store(8, Ordering::Release);
        state.begin_generation();
        assert!(!state.consume());
    }
}
