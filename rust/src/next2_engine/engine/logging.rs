use std::fs::File;
use std::io::Write;
use std::path::Path;
use std::sync::{Mutex, OnceLock};

struct Logger {
    file: Option<Mutex<File>>,
}

impl Logger {
    fn new(path: &Path) -> Self {
        // Android's default /data/local/tmp is not writable by regular apps.
        // Logging must also remain safe when called from a panic handler.
        Self {
            file: File::create(path).ok().map(Mutex::new),
        }
    }

    fn log(&self, msg: &str) {
        if let Some(file) = &self.file {
            if let Ok(mut file) = file.lock() {
                if writeln!(file, "[next2] {msg}").is_ok() {
                    // Keep the hot path buffered; do not flush each glyph log.
                    return;
                }
            }
        }
        // Unlike eprintln!, a failed stderr write cannot panic here.
        let _ = writeln!(std::io::stderr().lock(), "[next2] {msg}");
    }
}

static LOGGER: OnceLock<Logger> = OnceLock::new();

pub(crate) fn n2log(msg: &str) {
    LOGGER
        .get_or_init(|| Logger::new(&std::env::temp_dir().join("next2_debug.log")))
        .log(msg);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unavailable_log_file_does_not_panic_during_initialization_or_recovery() {
        // Creating a file at an existing directory fails on every supported OS,
        // reproducing the open failure of Android's inaccessible temp directory.
        let logger = Logger::new(&std::env::temp_dir());
        assert!(logger.file.is_none());
        logger.log("engine created");
        let failure = std::panic::catch_unwind(|| panic!("renderer failed"));
        assert!(failure.is_err());
        logger.log("FFI create_engine PANIC: renderer failed");
    }

    #[test]
    fn writable_log_file_records_messages() {
        let path = std::env::temp_dir().join(format!(
            "nipaplay-next2-logger-test-{}.log",
            std::process::id()
        ));
        let logger = Logger::new(&path);
        assert!(logger.file.is_some());
        logger.log("engine created");
        logger.log("frame ready");
        drop(logger);
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            "[next2] engine created\n[next2] frame ready\n"
        );
        std::fs::remove_file(path).unwrap();
    }
}
