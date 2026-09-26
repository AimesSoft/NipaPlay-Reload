#ifndef RUNNER_CLIPBOARD_IMAGE_H_
#define RUNNER_CLIPBOARD_IMAGE_H_

#include <flutter/binary_messenger.h>

/// 注册 "nipaplay/clipboard_image" 通道。
///
/// 提供 copyImageFile：把本地图片文件以 CF_HDROP 文件列表写入剪贴板，
/// 等价于在资源管理器中“复制文件”，聊天软件输入框可直接粘贴。
void RegisterClipboardImageChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_CLIPBOARD_IMAGE_H_