//! Command delivery with an interruptible, high-resolution Windows deadline.
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};

pub struct Sender<T> {
    inner: Option<mpsc::Sender<T>>,
    wake: Arc<Wake>,
}
pub struct Receiver<T> {
    inner: mpsc::Receiver<T>,
    wake: Arc<Wake>,
    #[cfg(target_os = "windows")]
    timer: Option<win::Handle>,
}

pub fn channel<T>() -> (Sender<T>, Receiver<T>) {
    let (tx, rx) = mpsc::channel();
    let wake = Arc::new(Wake::new());
    (
        Sender {
            inner: Some(tx),
            wake: wake.clone(),
        },
        Receiver {
            inner: rx,
            wake,
            #[cfg(target_os = "windows")]
            timer: win::timer(),
        },
    )
}
impl<T> Clone for Sender<T> {
    fn clone(&self) -> Self {
        Self {
            inner: self.inner.clone(),
            wake: self.wake.clone(),
        }
    }
}
impl<T> Sender<T> {
    pub fn send(&self, value: T) -> Result<(), mpsc::SendError<T>> {
        self.inner.as_ref().unwrap().send(value)?;
        self.wake.signal();
        Ok(())
    }
}
impl<T> Drop for Sender<T> {
    fn drop(&mut self) {
        // Disconnect the channel before waking its receiver.
        self.inner.take();
        self.wake.signal();
    }
}
impl<T> Receiver<T> {
    pub fn try_recv(&self) -> Result<T, mpsc::TryRecvError> {
        self.inner.try_recv()
    }
    pub fn recv_timeout(&self, timeout: Duration) -> Result<T, mpsc::RecvTimeoutError> {
        #[cfg(target_os = "windows")]
        if let (Some(event), Some(timer)) = (&self.wake.event, &self.timer) {
            let deadline = Instant::now() + timeout;
            loop {
                match self.inner.try_recv() {
                    Ok(value) => return Ok(value),
                    Err(mpsc::TryRecvError::Disconnected) => {
                        return Err(mpsc::RecvTimeoutError::Disconnected)
                    }
                    Err(mpsc::TryRecvError::Empty) => {}
                }
                let remaining = deadline.saturating_duration_since(Instant::now());
                if remaining.is_zero() {
                    return Err(mpsc::RecvTimeoutError::Timeout);
                }
                // Auto-reset event remains signaled if a sender races this arm.
                // Always recheck the queue after either handle wakes us.
                if !win::wait(event, timer, remaining) {
                    return self
                        .inner
                        .recv_timeout(deadline.saturating_duration_since(Instant::now()));
                }
            }
        }
        self.inner.recv_timeout(timeout)
    }
}

struct Wake {
    #[cfg(target_os = "windows")]
    event: Option<win::Handle>,
}
impl Wake {
    fn new() -> Self {
        Self {
            #[cfg(target_os = "windows")]
            event: win::event(),
        }
    }
    fn signal(&self) {
        #[cfg(target_os = "windows")]
        if let Some(event) = &self.event {
            unsafe {
                win::SetEvent(event.0);
            }
        }
    }
}

/// Registered and reverted on the render thread, only while animation is active.
pub struct MultimediaScheduling {
    #[cfg(target_os = "windows")]
    handle: win::RawHandle,
}
impl MultimediaScheduling {
    pub fn acquire() -> Option<Self> {
        #[cfg(target_os = "windows")]
        {
            let task: Vec<u16> = "Games\0".encode_utf16().collect();
            let mut index = 0;
            let handle = unsafe { win::AvSetMmThreadCharacteristicsW(task.as_ptr(), &mut index) };
            if handle.is_null() {
                return None;
            }
            unsafe {
                win::AvSetMmThreadPriority(handle, 1);
            } // AVRT_PRIORITY_HIGH
            Some(Self { handle })
        }
        #[cfg(not(target_os = "windows"))]
        {
            Some(Self {})
        }
    }
}
impl Drop for MultimediaScheduling {
    fn drop(&mut self) {
        #[cfg(target_os = "windows")]
        unsafe {
            win::AvRevertMmThreadCharacteristics(self.handle);
        }
    }
}

#[cfg(target_os = "windows")]
mod win {
    use super::Duration;
    use std::ffi::c_void;
    pub type RawHandle = *mut c_void;
    pub struct Handle(pub RawHandle);
    // Kernel event/timer handles support waits and signals across threads.
    unsafe impl Send for Handle {}
    unsafe impl Sync for Handle {}
    impl Drop for Handle {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn CreateEventW(
            attrs: *const c_void,
            manual: i32,
            initial: i32,
            name: *const u16,
        ) -> RawHandle;
        pub fn SetEvent(event: RawHandle) -> i32;
        fn CloseHandle(handle: RawHandle) -> i32;
        fn CreateWaitableTimerExW(
            attrs: *const c_void,
            name: *const u16,
            flags: u32,
            access: u32,
        ) -> RawHandle;
        fn SetWaitableTimerEx(
            timer: RawHandle,
            due: *const i64,
            period: i32,
            callback: Option<unsafe extern "system" fn(*mut c_void, u32, u32)>,
            arg: *mut c_void,
            reason: *const c_void,
            tolerance: u32,
        ) -> i32;
        fn WaitForMultipleObjects(
            count: u32,
            handles: *const RawHandle,
            all: i32,
            timeout: u32,
        ) -> u32;
        fn CancelWaitableTimer(timer: RawHandle) -> i32;
    }
    #[link(name = "avrt")]
    extern "system" {
        pub fn AvSetMmThreadCharacteristicsW(task: *const u16, index: *mut u32) -> RawHandle;
        pub fn AvSetMmThreadPriority(handle: RawHandle, priority: i32) -> i32;
        pub fn AvRevertMmThreadCharacteristics(handle: RawHandle) -> i32;
    }
    pub fn event() -> Option<Handle> {
        let raw = unsafe { CreateEventW(std::ptr::null(), 0, 0, std::ptr::null()) };
        if raw.is_null() {
            None
        } else {
            Some(Handle(raw))
        }
    }
    pub fn timer() -> Option<Handle> {
        // HIGH_RESOLUTION; SYNCHRONIZE | TIMER_MODIFY_STATE.
        let raw =
            unsafe { CreateWaitableTimerExW(std::ptr::null(), std::ptr::null(), 2, 0x100002) };
        if raw.is_null() {
            None
        } else {
            Some(Handle(raw))
        }
    }
    pub fn wait(event: &Handle, timer: &Handle, remaining: Duration) -> bool {
        let due = -((remaining.as_nanos().div_ceil(100)).min(i64::MAX as u128) as i64).max(1);
        let armed = unsafe {
            SetWaitableTimerEx(
                timer.0,
                &due,
                0,
                None,
                std::ptr::null_mut(),
                std::ptr::null(),
                0,
            )
        };
        if armed == 0 {
            return false;
        }
        let handles = [event.0, timer.0];
        let result = unsafe { WaitForMultipleObjects(2, handles.as_ptr(), 0, u32::MAX) };
        unsafe {
            CancelWaitableTimer(timer.0);
        }
        result <= 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn commands_interrupt_the_deadline_and_disconnect_wakes() {
        let (tx, rx) = channel();
        let worker = std::thread::spawn(move || {
            assert_eq!(rx.recv_timeout(Duration::from_secs(10)), Ok(42));
            assert_eq!(
                rx.recv_timeout(Duration::from_secs(10)),
                Err(mpsc::RecvTimeoutError::Disconnected)
            );
        });
        std::thread::sleep(Duration::from_millis(10));
        tx.send(42).unwrap();
        drop(tx);
        worker.join().unwrap();
    }
    #[test]
    fn coalesced_event_signals_do_not_lose_queued_commands() {
        let (tx, rx) = channel();
        for value in 0..100 {
            tx.send(value).unwrap();
        }
        for value in 0..100 {
            assert_eq!(rx.recv_timeout(Duration::from_millis(50)), Ok(value));
        }
        assert_eq!(
            rx.recv_timeout(Duration::from_millis(2)),
            Err(mpsc::RecvTimeoutError::Timeout)
        );
        tx.send(100).unwrap();
        assert_eq!(rx.recv_timeout(Duration::from_millis(50)), Ok(100));
    }
}
