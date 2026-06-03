#include "include/volume_controller/volume_controller_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "volume_controller_plugin.h"

void VolumeControllerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar)
{
    volume_controller::VolumeControllerPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarManager::GetInstance()
            ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
