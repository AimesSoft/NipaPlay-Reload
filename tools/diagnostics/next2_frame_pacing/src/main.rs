//! GPU completion-notification probe; no Flutter, fonts or video decoder.
//! Run with cargo run --manifest-path tools/diagnostics/next2_frame_pacing/Cargo.toml
use std::sync::{
    atomic::{AtomicBool, AtomicUsize, Ordering},
    Arc,
};
use std::time::{Duration, Instant};

fn main() {
    let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
        backends: wgpu::Backends::DX12,
        ..Default::default()
    });
    let adapter = pollster::block_on(instance.request_adapter(&Default::default())).unwrap();
    println!("GPU: {:?}", adapter.get_info());
    let (device, queue) = pollster::block_on(adapter.request_device(&Default::default())).unwrap();

    // Reproduce present.rs exactly, including the empty submit BEFORE callback
    // registration. A later Queue::submit services the previous callback.
    let ready = Arc::new(AtomicBool::new(false));
    let completed = Arc::new(AtomicUsize::new(0));
    for frame in 0..4 {
        queue.submit([]); // draw_to_present's submission
        println!(
            "frame {frame}: after draw submit, ready={}",
            ready.load(Ordering::Acquire)
        );
        ready.store(false, Ordering::Release);
        queue.submit([]);
        let r = ready.clone();
        let c = completed.clone();
        queue.on_submitted_work_done(move || {
            c.fetch_add(1, Ordering::Relaxed);
            r.store(true, Ordering::Release);
        });
        std::thread::sleep(Duration::from_millis(17));
        println!(
            "frame {frame}: after GPU idle 17ms, ready={}, callbacks={}",
            ready.load(Ordering::Acquire),
            completed.load(Ordering::Relaxed)
        );
    }
    device.poll(wgpu::PollType::wait_indefinitely()).unwrap();

    // Factorial comparison separates erased notifications from undriven
    // callbacks. The consumer deliberately uses the plugin's Sleep(16) loop.
    for clear_on_submit in [true, false] {
        for poll_completion in [false, true] {
            ready.store(false, Ordering::Release);
            let stop = Arc::new(AtomicBool::new(false));
            let notices = Arc::new(AtomicUsize::new(0));
            std::thread::scope(|scope| {
                let (r, s, n) = (ready.clone(), stop.clone(), notices.clone());
                let device_ref = &device;
                scope.spawn(move || {
                    while !s.load(Ordering::Acquire) {
                        if poll_completion {
                            device_ref.poll(wgpu::PollType::Poll).unwrap();
                        }
                        if r.swap(false, Ordering::AcqRel) {
                            n.fetch_add(1, Ordering::Relaxed);
                        }
                        std::thread::sleep(Duration::from_millis(16));
                    }
                });
                let start = Instant::now();
                for i in 0..240 {
                    queue.submit([]);
                    if clear_on_submit {
                        ready.store(false, Ordering::Release);
                    }
                    queue.submit([]);
                    let r = ready.clone();
                    queue.on_submitted_work_done(move || {
                        r.store(true, Ordering::Release);
                    });
                    let deadline = start + Duration::from_secs_f64((i + 1) as f64 / 120.0);
                    if let Some(wait) = deadline.checked_duration_since(Instant::now()) {
                        std::thread::sleep(wait);
                    }
                }
                stop.store(true, Ordering::Release);
            });
            device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
            println!("240 submissions / 2s: clear_on_submit={clear_on_submit}, poll_completion={poll_completion}, consumer_notifications={}", notices.load(Ordering::Relaxed));
        }
    }
}
