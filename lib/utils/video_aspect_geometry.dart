// 上游部分文件（如 video_surface_layout.dart）仍按 lib/utils 相对路径引用。
// 实现已随架构解耦迁入 nipaplay_core，这里 re-export 保持单一类型来源。
export 'package:nipaplay_core/utils/video_aspect_geometry.dart';
