#include "clipboard_image.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windows.h>

#include <cstring>
#include <memory>
#include <string>

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

void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
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