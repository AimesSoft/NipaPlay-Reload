#include "include/fvp/fvp_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "fvp_plugin.h"

void FvpPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  fvp::FvpPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
