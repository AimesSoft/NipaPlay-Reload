//! Opt-in, bounded frame tracing. Render/platform callbacks never write files.
use std::fs::OpenOptions;
use std::io::{BufWriter, Write};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{mpsc, Arc, OnceLock};
use std::time::{Duration, Instant};

#[derive(serde::Serialize)]
struct Event {
    t_us: u64,
    event: &'static str,
    engine: u64,
    frame: u64,
    a: i64,
    b: i64,
}

enum Record {
    Native(Event),
    Dart(u64, String),
}

struct Trace {
    start: Instant,
    tx: mpsc::SyncSender<Record>,
    dropped: Arc<AtomicU64>,
}

static TRACE: OnceLock<Option<Trace>> = OnceLock::new();

fn trace() -> Option<&'static Trace> {
    TRACE.get_or_init(|| {
        let path = std::env::var_os("NIPAPLAY_DFM_TRACE")?;
        if path.is_empty() { return None; }
        // A launcher supplies a unique path. Never overwrite an earlier trace.
        let file = OpenOptions::new().write(true).create_new(true).open(path).ok()?;
        let (tx, rx) = mpsc::sync_channel::<Record>(16384);
        let dropped = Arc::new(AtomicU64::new(0));
        let worker_dropped = Arc::clone(&dropped);
        std::thread::Builder::new().name("dfm-trace-writer".into()).spawn(move || {
            let mut out = BufWriter::with_capacity(65536, file);
            let _ = writeln!(out, "{{\"event\":\"header\",\"version\":1,\"clock\":\"native_monotonic_us\",\"max_seconds\":600}}");
            let mut bytes = 0usize;
            let mut last_flush = Instant::now();
            loop {
                let line = match rx.recv_timeout(Duration::from_secs(1)) {
                    Ok(Record::Native(event)) => serde_json::to_string(&event).ok(),
                    Ok(Record::Dart(t_us, data)) => Some(format!("{{\"event\":\"dart_batch\",\"t_us\":{t_us},\"data\":{data}}}")),
                    Err(mpsc::RecvTimeoutError::Timeout) => None,
                    Err(mpsc::RecvTimeoutError::Disconnected) => break,
                };
                if let Some(line) = line {
                    bytes += line.len() + 1;
                    if writeln!(out, "{line}").is_err() { break; }
                }
                let lost = worker_dropped.swap(0, Ordering::Relaxed);
                if lost > 0 { let _ = writeln!(out, "{{\"event\":\"native_dropped\",\"count\":{lost}}}"); }
                if last_flush.elapsed() >= Duration::from_secs(1) {
                    if out.flush().is_err() { break; }
                    last_flush = Instant::now();
                }
                if bytes >= 128 * 1024 * 1024 {
                    let _ = writeln!(out, "{{\"event\":\"size_limit\"}}");
                    break;
                }
            }
            let _ = out.flush();
        }).ok()?;
        Some(Trace { start: Instant::now(), tx, dropped })
    }).as_ref()
}

pub(crate) fn enabled() -> bool {
    trace().is_some_and(|t| t.start.elapsed() < Duration::from_secs(600))
}

pub(crate) fn record(event: &'static str, engine: u64, frame: u64, a: i64, b: i64) {
    if let Some(t) = trace() {
        if t.start.elapsed() >= Duration::from_secs(600) {
            return;
        }
        let item = Record::Native(Event {
            t_us: t.start.elapsed().as_micros() as u64,
            event,
            engine,
            frame,
            a,
            b,
        });
        if t.tx.try_send(item).is_err() {
            t.dropped.fetch_add(1, Ordering::Relaxed);
        }
    }
}

pub(crate) fn dart_batch(json: String) {
    if json.len() > 1024 * 1024 {
        return;
    }
    if let Some(t) = trace() {
        if t.start.elapsed() >= Duration::from_secs(600) {
            return;
        }
        if t.tx
            .try_send(Record::Dart(t.start.elapsed().as_micros() as u64, json))
            .is_err()
        {
            t.dropped.fetch_add(1, Ordering::Relaxed);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[ignore = "requires a unique NIPAPLAY_DFM_TRACE output path"]
    fn trace_writer_smoke() {
        assert!(enabled());
        record("test_native", 1, 7, 0, 0);
        dart_batch(r#"{"clock":"dart_timeline_us","dropped":0,"events":[]}"#.into());
        let path = std::env::var_os("NIPAPLAY_DFM_TRACE").unwrap();
        let start = Instant::now();
        loop {
            let data = std::fs::read_to_string(&path).unwrap();
            if data.contains("dart_batch") {
                let records: Vec<serde_json::Value> = data
                    .lines()
                    .map(|line| serde_json::from_str(line).unwrap())
                    .collect();
                assert!(records
                    .iter()
                    .any(|r| r["event"] == "test_native" && r["frame"] == 7));
                return;
            }
            assert!(start.elapsed() < Duration::from_secs(4));
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}
