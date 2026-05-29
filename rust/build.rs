fn main() {
    cc::Build::new()
        .cpp(true)
        .std("c++17")
        .opt_level(3)
        .file("cpp/similarity/src/similarity_engine.cpp")
        .file("cpp/similarity/src/pinyin_dict.cpp")
        .include("cpp/similarity/src") // similarity_engine.h 在此
        // 平台特定标志
        .flag_if_supported("-fno-exceptions")
        .flag_if_supported("-fno-rtti")
        .compile("similarity");
}
