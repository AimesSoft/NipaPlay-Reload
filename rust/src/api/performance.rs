#[cfg(target_os = "macos")]
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
    cfg!(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "windows"
    ))
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

    let ticks_per_sec = unsafe { libc::sysconf(libc::_SC_CLK_TCK) } as f64;
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
        let user_us = usage.ru_utime.tv_sec * 1_000_000 + i64::from(usage.ru_utime.tv_usec);
        let sys_us = usage.ru_stime.tv_sec * 1_000_000 + i64::from(usage.ru_stime.tv_usec);
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
        used_key
            .unwrap_or("unknown")
            .replace(' ', "_")
            .replace('%', "pct")
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

// ---------------------------------------------------------------------------
// Windows native Win32 API sampling (no PowerShell / child processes)
// ---------------------------------------------------------------------------

/// Manual FFI for GetProcessTimes / GetProcessMemoryInfo (lightweight, no crate needed).
#[cfg(target_os = "windows")]
#[allow(non_camel_case_types)]
mod win32_kernel {
    use std::ffi::c_void;

    pub type HANDLE = *mut c_void;
    pub type BOOL = i32;

    #[repr(C)]
    pub struct FILETIME {
        pub dw_low_date_time: u32,
        pub dw_high_date_time: u32,
    }

    #[repr(C)]
    pub struct PROCESS_MEMORY_COUNTERS {
        pub cb: u32,
        pub page_fault_count: u32,
        pub peak_working_set_size: usize,
        pub working_set_size: usize,
        pub quota_peak_paged_pool_usage: usize,
        pub quota_paged_pool_usage: usize,
        pub quota_peak_non_paged_pool_usage: usize,
        pub quota_non_paged_pool_usage: usize,
        pub pagefile_usage: usize,
        pub peak_pagefile_usage: usize,
    }

    extern "system" {
        pub fn GetCurrentProcess() -> HANDLE;
        pub fn GetProcessTimes(
            hprocess: HANDLE,
            creation_time: *mut FILETIME,
            exit_time: *mut FILETIME,
            kernel_time: *mut FILETIME,
            user_time: *mut FILETIME,
        ) -> BOOL;
        pub fn GetProcessMemoryInfo(
            process: HANDLE,
            counters: *mut PROCESS_MEMORY_COUNTERS,
            cb: u32,
        ) -> BOOL;
    }
}

#[cfg(target_os = "windows")]
use self::win32_kernel::*;

#[cfg(target_os = "windows")]
fn filetime_to_micros(ft: &FILETIME) -> i64 {
    let val = ((ft.dw_high_date_time as i64) << 32) | (ft.dw_low_date_time as i64);
    val / 10 // FILETIME is in 100-nanosecond intervals
}

#[cfg(target_os = "windows")]
fn sample_process_cpu_windows() -> Result<RustCpuSample, String> {
    unsafe {
        let process = GetCurrentProcess();
        let mut creation = FILETIME {
            dw_low_date_time: 0,
            dw_high_date_time: 0,
        };
        let mut exit_ft = FILETIME {
            dw_low_date_time: 0,
            dw_high_date_time: 0,
        };
        let mut kernel = FILETIME {
            dw_low_date_time: 0,
            dw_high_date_time: 0,
        };
        let mut user = FILETIME {
            dw_low_date_time: 0,
            dw_high_date_time: 0,
        };

        if GetProcessTimes(process, &mut creation, &mut exit_ft, &mut kernel, &mut user) == 0 {
            return Err(format!(
                "GetProcessTimes failed: {}",
                std::io::Error::last_os_error()
            ));
        }

        let cpu_micros = filetime_to_micros(&kernel) + filetime_to_micros(&user);

        Ok(RustCpuSample {
            process_cpu_micros: cpu_micros,
            timestamp_ms: now_millis(),
            logical_cpus: num_cpus(),
        })
    }
}

#[cfg(target_os = "windows")]
fn sample_process_memory_windows() -> Result<RustMemorySample, String> {
    unsafe {
        let mut counters: PROCESS_MEMORY_COUNTERS = std::mem::zeroed();
        counters.cb = std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32;

        if GetProcessMemoryInfo(GetCurrentProcess(), &mut counters, counters.cb) == 0 {
            return Err(format!(
                "GetProcessMemoryInfo failed: {}",
                std::io::Error::last_os_error()
            ));
        }

        Ok(RustMemorySample {
            rss_mb: counters.working_set_size as f64 / 1024.0 / 1024.0,
        })
    }
}

// ---------------------------------------------------------------------------
// GPU sampling via the `windows` crate PDH bindings
// ---------------------------------------------------------------------------

#[cfg(target_os = "windows")]
use windows::Win32::System::Performance::{
    PdhAddEnglishCounterW, PdhCloseQuery, PdhCollectQueryData, PdhGetFormattedCounterArrayW,
    PdhOpenQueryW, PDH_FMT_COUNTERVALUE_ITEM_W, PDH_FMT_DOUBLE,
};

#[cfg(target_os = "windows")]
static mut PDH_QUERY: Option<isize> = None;
#[cfg(target_os = "windows")]
static mut PDH_COUNTER: isize = 0;

const PDH_MORE_DATA: u32 = 0x8000_07D2;

#[cfg(target_os = "windows")]
fn sample_gpu_windows() -> Result<RustGpuSample, String> {
    unsafe {
        if PDH_QUERY.is_none() {
            let mut query: isize = 0;
            let result = PdhOpenQueryW(windows::core::PCWSTR(std::ptr::null()), 0, &mut query);
            if result != 0 {
                return Err(format!("PdhOpenQueryW failed with code {result}"));
            }

            let path: Vec<u16> = "\\GPU Engine(*)\\Utilization Percentage"
                .encode_utf16()
                .chain(std::iter::once(0))
                .collect();

            let mut counter: isize = 0;
            let result =
                PdhAddEnglishCounterW(query, windows::core::PCWSTR(path.as_ptr()), 0, &mut counter);
            if result != 0 {
                let _ = PdhCloseQuery(query);
                return Err(format!("PdhAddEnglishCounterW failed with code {result}"));
            }

            PDH_QUERY = Some(query);
            PDH_COUNTER = counter;
        }

        let query = PDH_QUERY.unwrap();

        let result = PdhCollectQueryData(query);
        if result != 0 {
            return Err(format!(
                "PdhCollectQueryData (1st) failed with code {result}"
            ));
        }

        std::thread::sleep(std::time::Duration::from_millis(250));

        let result = PdhCollectQueryData(query);
        if result != 0 {
            return Err(format!(
                "PdhCollectQueryData (2nd) failed with code {result}"
            ));
        }

        let mut buf_size: u32 = 0;
        let mut item_count: u32 = 0;
        let result = PdhGetFormattedCounterArrayW(
            PDH_COUNTER,
            PDH_FMT_DOUBLE,
            &mut buf_size,
            &mut item_count,
            None,
        );
        if result != 0 && result != PDH_MORE_DATA {
            return Err(format!(
                "PdhGetFormattedCounterArrayW (size) failed with code {result}"
            ));
        }

        if item_count == 0 || buf_size == 0 {
            return Ok(RustGpuSample {
                gpu_percent: 0.0,
                source: "windows_pdh".to_string(),
            });
        }

        let item_size = std::mem::size_of::<PDH_FMT_COUNTERVALUE_ITEM_W>() as u32;
        let alloc = ((buf_size / item_size) as usize).saturating_add(8);
        let mut items: Vec<PDH_FMT_COUNTERVALUE_ITEM_W> = Vec::with_capacity(alloc);
        items.set_len(alloc);

        let result = PdhGetFormattedCounterArrayW(
            PDH_COUNTER,
            PDH_FMT_DOUBLE,
            &mut buf_size,
            &mut item_count,
            Some(items.as_mut_ptr()),
        );
        if result != 0 {
            return Err(format!(
                "PdhGetFormattedCounterArrayW (data) failed with code {result}"
            ));
        }

        let values: Vec<f64> = items[..item_count as usize]
            .iter()
            .map(|item| item.FmtValue.Anonymous.doubleValue)
            .filter(|v| *v > 0.0)
            .collect();

        let gpu_pct = if values.is_empty() {
            0.0
        } else {
            (values.iter().sum::<f64>() / values.len() as f64).clamp(0.0, 100.0)
        };

        Ok(RustGpuSample {
            gpu_percent: gpu_pct,
            source: "windows_pdh".to_string(),
        })
    }
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
