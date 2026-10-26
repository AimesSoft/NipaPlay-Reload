#include "clipboard_image.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <gdiplus.h>

#include <shlobj.h>

#include <cstring>
#include <algorithm>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <stdexcept>

namespace {

// 通道需与引擎同生命周期，用文件级静态量持有。
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_clipboard_channel;

// 构造 CF_HDROP 数据块：DROPFILES 头 + 双 null 结尾的宽字符路径列表。
HGLOBAL BuildFileDropHandle(const std::wstring& path) {
  const SIZE_T header_size = sizeof(DROPFILES);
  const SIZE_T path_bytes = (path.size() + 1) * sizeof(wchar_t);
  // 路径列表以双 null 结尾，额外预留一个宽字符。
  const SIZE_T total_size = header_size + path_bytes + sizeof(wchar_t);

  HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, total_size);
  if (handle == nullptr) {
    return nullptr;
  }

  auto* drop = static_cast<DROPFILES*>(::GlobalLock(handle));
  if (drop == nullptr) {
    ::GlobalFree(handle);
    return nullptr;
  }

  drop->pFiles = static_cast<DWORD>(header_size);
  drop->fWide = TRUE;

  auto* path_buffer = reinterpret_cast<wchar_t*>(
      reinterpret_cast<unsigned char*>(drop) + header_size);
  ::memcpy(path_buffer, path.c_str(), path_bytes);
  path_buffer[path.size()] = L'\0';
  path_buffer[path.size() + 1] = L'\0';

  ::GlobalUnlock(handle);
  return handle;
}

// 把文件路径写入剪贴板；成功后剪贴板接管内存块所有权。
bool WriteFileToClipboard(const std::wstring& path) {
  if (!::OpenClipboard(nullptr)) {
    return false;
  }

  ::EmptyClipboard();

  HGLOBAL handle = BuildFileDropHandle(path);
  bool written = false;
  if (handle != nullptr) {
    if (::SetClipboardData(CF_HDROP, handle) != nullptr) {
      // 所有权已移交系统，不能再释放。
      written = true;
    } else {
      ::GlobalFree(handle);
    }
  }

  ::CloseClipboard();
  return written;
}

std::wstring WideFromUtf8(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = ::MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                        static_cast<int>(value.size()), wide.data(), size);
  return wide;
}

std::filesystem::path AttachmentPath(const std::filesystem::path& directory,
                                     const std::wstring& extension) {
  GUID id;
  if (FAILED(::CoCreateGuid(&id))) {
    throw std::runtime_error("Cannot create an attachment name");
  }
  wchar_t name[40];
  ::StringFromGUID2(id, name, 40);
  return directory / (std::wstring(L"clipboard-") + name + extension);
}

void ReadImageFiles(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  const auto entry = args == nullptr ? nullptr : [&]() -> const std::string* {
    auto item = args->find(flutter::EncodableValue("directory"));
    return item == args->end() ? nullptr : std::get_if<std::string>(&item->second);
  }();
  if (entry == nullptr || entry->empty()) {
    result->Error("INVALID_ARGUMENTS", "An attachment directory is required");
    return;
  }
  if (!::OpenClipboard(nullptr)) {
    result->Error("CLIPBOARD_READ_FAILED", "The clipboard is busy; try again");
    return;
  }
  struct ClipboardGuard {
    ~ClipboardGuard() { ::CloseClipboard(); }
  } clipboard_guard;
  try {
    const std::filesystem::path directory(WideFromUtf8(*entry));
    std::filesystem::create_directories(directory);
    flutter::EncodableList paths;
    if (auto drop = static_cast<HDROP>(::GetClipboardData(CF_HDROP))) {
      const auto count = ::DragQueryFileW(drop, 0xffffffff, nullptr, 0);
      for (UINT i = 0; i < count; ++i) {
        const auto length = ::DragQueryFileW(drop, i, nullptr, 0);
        std::wstring name(length + 1, L'\0');
        ::DragQueryFileW(drop, i, name.data(), length + 1);
        name.resize(length);
        const std::filesystem::path source(name);
        auto ext = source.extension().wstring();
        std::transform(ext.begin(), ext.end(), ext.begin(),
                       [](wchar_t c) { return static_cast<wchar_t>(::towlower(c)); });
        if (ext != L".png" && ext != L".jpg" && ext != L".jpeg" &&
            ext != L".gif" && ext != L".webp" && ext != L".heic" &&
            ext != L".heif" && ext != L".bmp" && ext != L".tif" && ext != L".tiff") {
          continue;
        }
        const auto target = AttachmentPath(directory, ext);
        std::filesystem::copy_file(source, target);
        paths.emplace_back(target.u8string());
      }
    }
    if (!paths.empty()) {
      result->Success(flutter::EncodableValue(paths));
      return;
    }
    // Browser copies may contain a lossless PNG (including its alpha channel).
    const auto png_format = ::RegisterClipboardFormatW(L"PNG");
    if (auto handle = ::GetClipboardData(png_format)) {
      const auto size = ::GlobalSize(handle);
      const auto* bytes = static_cast<const char*>(::GlobalLock(handle));
      if (bytes != nullptr) {
        const auto target = AttachmentPath(directory, L".png");
        std::ofstream output(target, std::ios::binary);
        output.write(bytes, static_cast<std::streamsize>(size));
        ::GlobalUnlock(handle);
        output.close();
        if (!output) throw std::runtime_error("Cannot save the clipboard image");
        paths.emplace_back(target.u8string());
      }
    }
    if (paths.empty()) {
      // Windows synthesizes CF_BITMAP for screenshot DIB/DIBV5 clipboard data.
      if (auto bitmap = static_cast<HBITMAP>(::GetClipboardData(CF_BITMAP))) {
        struct GdiGuard {
          ULONG_PTR token = 0;
          ~GdiGuard() { if (token != 0) Gdiplus::GdiplusShutdown(token); }
        } gdi;
        Gdiplus::GdiplusStartupInput startup;
        if (Gdiplus::GdiplusStartup(&gdi.token, &startup, nullptr) != Gdiplus::Ok) {
          throw std::runtime_error("Cannot decode the clipboard bitmap");
        }
        std::unique_ptr<Gdiplus::Bitmap> image(Gdiplus::Bitmap::FromHBITMAP(bitmap, nullptr));
        const CLSID png_encoder = {0x557cf406, 0x1a04, 0x11d3,
                                  {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
        const auto target = AttachmentPath(directory, L".png");
        if (!image || image->Save(target.c_str(), &png_encoder, nullptr) != Gdiplus::Ok) {
          throw std::runtime_error("Cannot save the clipboard bitmap");
        }
        paths.emplace_back(target.u8string());
      }
    }
    result->Success(flutter::EncodableValue(paths));
  } catch (const std::exception&) {
    result->Error("CLIPBOARD_READ_FAILED", "Cannot save the clipboard image; try again");
  }
}

void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "readImageFiles") {
    ReadImageFiles(call, std::move(result));
    return;
  }
  if (call.method_name() != "copyImageFile") {
    result->NotImplemented();
    return;
  }

  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    result->Error("INVALID_ARGUMENTS", "Arguments are required");
    return;
  }

  const auto path_entry = arguments->find(flutter::EncodableValue("path"));
  if (path_entry == arguments->end()) {
    result->Error("INVALID_ARGUMENTS", "A file path is required");
    return;
  }
  const auto* path_value = std::get_if<std::string>(&path_entry->second);
  if (path_value == nullptr || path_value->empty()) {
    result->Error("INVALID_ARGUMENTS", "A non-empty file path is required");
    return;
  }

  const std::wstring wide_path = WideFromUtf8(*path_value);
  if (wide_path.empty()) {
    result->Error("INVALID_ARGUMENTS", "The file path could not be decoded");
    return;
  }

  const DWORD attributes = ::GetFileAttributesW(wide_path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
    result->Error("FILE_NOT_FOUND", "The file to copy does not exist",
                  *path_value);
    return;
  }

  if (!WriteFileToClipboard(wide_path)) {
    result->Error("CLIPBOARD_WRITE_FAILED",
                  "Failed to write the file to the clipboard");
    return;
  }

  result->Success(flutter::EncodableValue(true));
}

}  // namespace

void RegisterClipboardImageChannel(flutter::BinaryMessenger* messenger) {
  g_clipboard_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "nipaplay/clipboard_image",
          &flutter::StandardMethodCodec::GetInstance());
  g_clipboard_channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}
