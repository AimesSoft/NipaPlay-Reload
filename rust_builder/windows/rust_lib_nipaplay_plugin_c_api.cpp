#include "include/rust_lib_nipaplay/rust_lib_nipaplay_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "rust_lib_nipaplay_plugin.h"

void RustLibNipaplayPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  rust_lib_nipaplay::RustLibNipaplayPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
