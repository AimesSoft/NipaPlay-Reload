// A disposable reader using the Erika library already shipped by NipaPlay.
// No Flutter, window, playback session or database is opened. The parent owns
// the deadline and process lifetime; OS teardown releases all native threads.
#include <cstdio>
#include <cstdlib>
#include <string>
#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

static int probe(void* library, const char* path) {
#ifdef _WIN32
  auto symbol = [library](const char* name) {
    return reinterpret_cast<void*>(GetProcAddress(static_cast<HMODULE>(library), name));
  };
#else
  auto symbol = [library](const char* name) { return dlsym(library, name); };
#endif
  auto create = reinterpret_cast<void* (*)()>(symbol("erika_presenter_create"));
  auto open = reinterpret_cast<int (*)(void*, const char*)>(symbol("erika_presenter_open"));
  auto invoke = reinterpret_cast<char* (*)(void*, const char*, const char*)>(symbol("erika_presenter_invoke_json"));
  auto poll = reinterpret_cast<char* (*)(void*)>(symbol("erika_presenter_poll_event_json"));
  auto last_error = reinterpret_cast<char* (*)()>(symbol("erika_last_error_message"));
  auto release = reinterpret_cast<void (*)(char*)>(symbol("erika_string_free"));
  if (!create || !open || !invoke || !poll || !last_error || !release) {
    std::fputs("Bundled Erika lacks the media probe ABI.\n", stderr);
    return 2;
  }
  void* player = create();
  if (!player || open(player, path) != 0) {
    char* error = last_error();
    std::fprintf(stderr, "%s\n", error ? error : "Erika could not open the media.");
    if (error) release(error);
    return 3;
  }
  char* container = invoke(player, "container", "{}");
  char* tracks = invoke(player, "tracks", "{}");
  if (!container || !tracks) {
    std::fputs("Erika returned no media facts.\n", stderr);
    return 4;
  }
  std::printf("{\"container\":%s,\"tracks\":%s,\"events\":[", container, tracks);
  release(container);
  release(tracks);
  for (int i = 0; i < 256; ++i) {
    char* event = poll(player);
    if (!event) break;
    std::printf("%s%s", i ? "," : "", event);
    release(event);
  }
  std::fputs("]}\n", stdout);
  return 0;
}

#ifdef _WIN32
static std::string utf8(const wchar_t* value) {
  int size = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), size, nullptr, nullptr);
  return result;
}
int wmain(int argc, wchar_t** argv) {
  if (argc != 3) return 1;
  // Dependencies resolve alongside the installed Erika library.
  HMODULE library = LoadLibraryExW(argv[1], nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  if (!library) {
    std::fprintf(stderr, "Cannot load bundled Erika (Windows error %lu).\n", GetLastError());
    return 2;
  }
  int code = probe(library, utf8(argv[2]).c_str());
#else
int main(int argc, char** argv) {
  if (argc != 3) return 1;
  void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    std::fprintf(stderr, "Cannot load bundled Erika: %s\n", dlerror());
    return 2;
  }
  int code = probe(library, argv[2]);
#endif
  std::fflush(stdout);
  std::fflush(stderr);
  // Do not join a media library's threads in the host. This process owns no
  // writable application state; exit releases its entire native address space.
  std::_Exit(code);
}
