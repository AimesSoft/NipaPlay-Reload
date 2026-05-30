fn main() {
    let is_release = std::env::var("PROFILE").map(|s| s == "release").unwrap_or(false);

    let mut build = cc::Build::new();
    build
        .cpp(true)
        .std("c++17")
        .file("cpp/similarity/src/similarity_engine.cpp")
        .file("cpp/similarity/src/pinyin_dict.cpp")
        .include("cpp/similarity/src") // similarity_engine.h 在此
        // 注意：不使用 -fno-exceptions，C API 的 try-catch 需要 C++ 异常支持
        // 来捕获 FFI 边界上的任何异常，防止进程崩溃
        .flag_if_supported("-fno-rtti")
        .flag_if_supported("/utf-8");  // MSVC: 防止 C4819 编码警告导致错误

    if is_release {
        // Release: -O3 -ffast-math (equivalent to -Ofast)
        build.opt_level(3);
        build.flag_if_supported("-ffast-math"); // safe: no isnan/isinf, integer-only std::abs
        build.flag_if_supported("/fp:fast");    // MSVC equivalent
    } else {
        // Debug: -Og (optimize for debugging, preserve stack frames)
        build.opt_level(0);
        build.flag_if_supported("-Og");
    }

    // MSVC: cc crate 在某些环境（如 Flutter cargokit）中无法自动检测 INCLUDE 路径，
    // 需要手动添加 MSVC 和 Windows SDK 的 include 目录。
    if std::env::var("CARGO_CFG_TARGET_OS").map(|s| s == "windows").unwrap_or(false) {
        if let Ok(msvc_dir) = std::env::var("VCToolsInstallDir") {
            // VCToolsInstallDir 通常指向 .../MSVC/<version>/
            build.include(format!("{}include", msvc_dir));
        }
        // 尝试通过 WindowsSdkDir 找 UCRT include
        if let Ok(sdk_dir) = std::env::var("WindowsSdkDir") {
            if let Ok(sdk_ver) = std::env::var("WindowsSDKVersion") {
                let ver = sdk_ver.trim_end_matches('\\');
                build.include(format!("{}Include\\{}\\ucrt", sdk_dir, ver));
            }
        }
    }

    build.compile("similarity");
}
