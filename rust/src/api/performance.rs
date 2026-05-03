#[cfg(any(target_os = "macos", target_os = "windows"))]
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct RustPerformanceSample {
    pub cpu_process_percent: Option<f64>,
    pub memory_rss_mb: Option<f64>,
    pub gpu_percent: Option<f64>,
    pub source: String,
    pub timestamp_ms: i64,
    pub note: Option<String>,
}

#[derive(Debug)]
pub struct RustCpuSample {
    pub process_cpu_micros: i64,
    pub timestamp_ms: i64,
    pub logical_cpus: i32,
}

#[derive(Debug)]
pub struct RustMemorySample {
    pub rss_mb: f64,
}

#[derive(Debug)]
pub struct RustGpuSample {
    pub gpu_percent: f64,
    pub source: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn is_performance_probe_available() -> bool {
    cfg!(any(target_os = "linux", target_os = "macos", target_os = "windows"))
}

pub fn sample_performance() -> RustPerformanceSample {
    let timestamp_ms = now_millis();
    let cpu = sample_process_cpu().ok();
    let memory = sample_process_memory().ok();
    let gpu = sample_gpu().ok();

    RustPerformanceSample {
        cpu_process_percent: None,
        memory_rss_mb: memory.map(|m| m.rss_mb),
        gpu_percent: gpu.as_ref().map(|g| g.gpu_percent),
        source: gpu
            .map(|g| g.source)
            .unwrap_or_else(|| "process_only".to_string()),
        timestamp_ms,
        note: if cpu.is_none() {
            Some("cpu_unavailable".to_string())
        } else {
            None
        },
    }
}

pub fn sample_cpu_counters() -> Result<RustCpuSample, String> {
    sample_process_cpu()
}

pub fn sample_memory_rss_mb() -> Result<f64, String> {
    Ok(sample_process_memory()?.rss_mb)
}

pub fn sample_gpu_percent() -> Result<RustGpuSample, String> {
    sample_gpu()
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn sample_process_cpu() -> Result<RustCpuSample, String> {
    #[cfg(target_os = "linux")]
    {
        return sample_process_cpu_linux();
    }
    #[cfg(target_os = "macos")]
    {
        return sample_process_cpu_macos();
    }
    #[cfg(target_os = "windows")]
    {
        return sample_process_cpu_windows();
    }
    #[allow(unreachable_code)]
    Err("unsupported_platform".to_string())
}

fn sample_process_memory() -> Result<RustMemorySample, String> {
    #[cfg(target_os = "linux")]
    {
        return sample_process_memory_linux();
    }
    #[cfg(target_os = "macos")]
    {
        return sample_process_memory_macos();
    }
    #[cfg(target_os = "windows")]
    {
        return sample_process_memory_windows();
    }
    #[allow(unreachable_code)]
    Err("unsupported_platform".to_string())
}

fn sample_gpu() -> Result<RustGpuSample, String> {
    #[cfg(target_os = "macos")]
    {
        return sample_gpu_macos();
    }
    #[cfg(target_os = "windows")]
    {
        return sample_gpu_windows();
    }
    #[cfg(target_os = "linux")]
    {
        return sample_gpu_linux();
    }
    #[allow(unreachable_code)]
    Err("unsupported_platform".to_string())
}

#[cfg(target_os = "linux")]
fn sample_process_cpu_linux() -> Result<RustCpuSample, String> {
    use std::fs;

    let pid = std::process::id();
    let path = format!("/proc/{pid}/stat");
    let content = fs::read_to_string(&path).map_err(|e| format!("read {path} failed: {e}"))?;

    let right_paren = content
        .rfind(')')
        .ok_or_else(|| "invalid /proc stat format".to_string())?;
    let rest = content
        .get((right_paren + 2)..)
        .ok_or_else(|| "invalid /proc stat fields".to_string())?;
    let fields: Vec<&str> = rest.split_whitespace().collect();
    if fields.len() < 13 {
        return Err("insufficient /proc stat fields".to_string());
    }

    let utime = fields[11]
        .parse::<i64>()
        .map_err(|e| format!("parse utime failed: {e}"))?;
    let stime = fields[12]
        .parse::<i64>()
        .map_err(|e| format!("parse stime failed: {e}"))?;

    let ticks_per_sec = 100.0;
    let cpu_micros = (((utime + stime) as f64) / ticks_per_sec * 1_000_000.0) as i64;

    Ok(RustCpuSample {
        process_cpu_micros: cpu_micros,
        timestamp_ms: now_millis(),
        logical_cpus: num_cpus(),
    })
}

#[cfg(target_os = "linux")]
fn sample_process_memory_linux() -> Result<RustMemorySample, String> {
    use std::fs;

    let pid = std::process::id();
    let path = format!("/proc/{pid}/status");
    let content = fs::read_to_string(&path).map_err(|e| format!("read {path} failed: {e}"))?;

    let mut rss_kb: Option<f64> = None;
    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("VmRSS:") {
            let first = rest.split_whitespace().next();
            if let Some(raw) = first {
                if let Ok(parsed) = raw.parse::<f64>() {
                    rss_kb = Some(parsed);
                    break;
                }
            }
        }
    }

    let rss_kb = rss_kb.ok_or_else(|| "VmRSS not found".to_string())?;
    Ok(RustMemorySample {
        rss_mb: rss_kb / 1024.0,
    })
}

#[cfg(target_os = "macos")]
fn sample_process_cpu_macos() -> Result<RustCpuSample, String> {
    let cpu_micros = unsafe {
        let mut usage: libc::rusage = std::mem::zeroed();
        if libc::getrusage(libc::RUSAGE_SELF, &mut usage) != 0 {
            return Err(format!(
                "getrusage failed: {}",
                std::io::Error::last_os_error()
            ));
        }
        let user_us =
            usage.ru_utime.tv_sec * 1_000_000 + i64::from(usage.ru_utime.tv_usec);
        let sys_us =
            usage.ru_stime.tv_sec * 1_000_000 + i64::from(usage.ru_stime.tv_usec);
        user_us + sys_us
    };

    Ok(RustCpuSample {
        process_cpu_micros: cpu_micros,
        timestamp_ms: now_millis(),
        logical_cpus: num_cpus(),
    })
}

#[cfg(target_os = "macos")]
fn sample_process_memory_macos() -> Result<RustMemorySample, String> {
    let rss_bytes = unsafe {
        let mut info: libc::mach_task_basic_info = std::mem::zeroed();
        let mut count = libc::MACH_TASK_BASIC_INFO_COUNT;

        let kr = libc::task_info(
            libc::mach_task_self(),
            libc::MACH_TASK_BASIC_INFO,
            (&mut info as *mut libc::mach_task_basic_info).cast::<libc::integer_t>(),
            &mut count,
        );

        if kr != libc::KERN_SUCCESS {
            return Err(format!("task_info failed: kern_return_t={kr}"));
        }

        info.resident_size as f64
    };

    Ok(RustMemorySample {
        rss_mb: rss_bytes / 1024.0 / 1024.0,
    })
}

#[cfg(target_os = "macos")]
fn sample_gpu_macos() -> Result<RustGpuSample, String> {
    let output = Command::new("ioreg")
        .args(["-r", "-d", "1", "-c", "AGXAccelerator"])
        .output()
        .map_err(|e| format!("exec ioreg failed: {e}"))?;

    if !output.status.success() {
        return Err(format!("ioreg exited with {}", output.status));
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let mut parsed: Option<f64> = None;
    let mut used_key: Option<&'static str> = None;

    for key in [
        "Device Utilization %",
        "Renderer Utilization %",
        "Tiler Utilization %",
    ] {
        if let Some(value) = parse_ioreg_percent_stat(&text, key) {
            parsed = Some(value.clamp(0.0, 100.0));
            used_key = Some(key);
            break;
        }
    }

    let value = parsed.ok_or_else(|| {
        "gpu utilization key not found in ioreg PerformanceStatistics".to_string()
    })?;
    let source = format!(
        "macos_ioreg_performance_statistics_{}",
        used_key.unwrap_or("unknown").replace(' ', "_").replace('%', "pct")
    );

    Ok(RustGpuSample {
        gpu_percent: value,
        source,
    })
}

#[cfg(target_os = "macos")]
fn parse_ioreg_percent_stat(text: &str, key: &str) -> Option<f64> {
    // ioreg can emit either `"Key" = 85` or `"Key"=85`; handle both.
    let quoted = format!("\"{key}\"");
    let start = text.find(&quoted)?;
    let slice = &text[start + quoted.len()..];
    let eq_pos = slice.find('=')?;
    let after_eq = &slice[eq_pos + 1..];

    let number: String = after_eq
        .chars()
        .skip_while(|c| c.is_whitespace())
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();

    if number.is_empty() {
        return None;
    }

    number.parse::<f64>().ok()
}

#[cfg(target_os = "windows")]
fn sample_process_cpu_windows() -> Result<RustCpuSample, String> {
    let pid = std::process::id().to_string();
    let command = format!("(Get-Process -Id {pid} | Select-Object -ExpandProperty CPU)");
    let output = Command::new("powershell")
        .args(["-NoProfile", "-Command", &command])
        .output()
        .map_err(|e| format!("exec powershell failed: {e}"))?;

    if !output.status.success() {
        return Err(format!("powershell exited with {}", output.status));
    }

    let raw = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let seconds = raw
        .parse::<f64>()
        .map_err(|e| format!("parse CPU seconds failed ({raw}): {e}"))?;

    Ok(RustCpuSample {
        process_cpu_micros: (seconds * 1_000_000.0) as i64,
        timestamp_ms: now_millis(),
        logical_cpus: num_cpus(),
    })
}

#[cfg(target_os = "windows")]
fn sample_process_memory_windows() -> Result<RustMemorySample, String> {
    let pid = std::process::id().to_string();
    let command = format!("(Get-Process -Id {pid} | Select-Object -ExpandProperty WorkingSet64)");
    let output = Command::new("powershell")
        .args(["-NoProfile", "-Command", &command])
        .output()
        .map_err(|e| format!("exec powershell failed: {e}"))?;

    if !output.status.success() {
        return Err(format!("powershell exited with {}", output.status));
    }

    let raw = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let bytes = raw
        .parse::<f64>()
        .map_err(|e| format!("parse WorkingSet64 failed ({raw}): {e}"))?;

    Ok(RustMemorySample {
        rss_mb: bytes / 1024.0 / 1024.0,
    })
}

#[cfg(target_os = "windows")]
fn sample_gpu_windows() -> Result<RustGpuSample, String> {
    let command = "(Get-Counter '\\GPU Engine(*)\\Utilization Percentage').CounterSamples | Where-Object {$_.CookedValue -ge 0} | Measure-Object CookedValue -Average | Select-Object -ExpandProperty Average";
    let output = Command::new("powershell")
        .args(["-NoProfile", "-Command", command])
        .output()
        .map_err(|e| format!("exec powershell failed: {e}"))?;

    if !output.status.success() {
        return Err(format!("powershell exited with {}", output.status));
    }

    let raw = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let value = raw
        .parse::<f64>()
        .map_err(|e| format!("parse gpu counter failed ({raw}): {e}"))?
        .clamp(0.0, 100.0);

    Ok(RustGpuSample {
        gpu_percent: value,
        source: "windows_get_counter_gpu_engine".to_string(),
    })
}

#[cfg(target_os = "linux")]
fn sample_gpu_linux() -> Result<RustGpuSample, String> {
    Err("gpu_sampling_not_implemented_on_linux".to_string())
}

fn num_cpus() -> i32 {
    std::thread::available_parallelism()
        .map(|n| n.get() as i32)
        .unwrap_or(1)
}
