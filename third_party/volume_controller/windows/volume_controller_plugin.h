#ifndef FLUTTER_PLUGIN_VOLUME_CONTROLLER_PLUGIN_H_
#define FLUTTER_PLUGIN_VOLUME_CONTROLLER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

#include "include/volume_controller/constants.h"
#include "include/volume_controller/volume_controller.h"
#include "include/volume_controller/volume_listener.h"
#include "include/volume_controller/volume_stream_handler.h"
#include "include/volume_controller/helper.h"

namespace volume_controller
{
    class VolumeControllerPlugin : public flutter::Plugin
    {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        VolumeControllerPlugin();
        virtual ~VolumeControllerPlugin();

        // Disallow copy and assign.
        VolumeControllerPlugin(const VolumeControllerPlugin &) = delete;
        VolumeControllerPlugin &operator=(const VolumeControllerPlugin &) = delete;

        // Called when a method is called on this plugin's channel from Dart.
        void HandleMethodCall(
            const flutter::MethodCall<flutter::EncodableValue> &method_call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    private:
        volume_controller::VolumeController &volume_controller_;
    };

} // namespace volume_controller

#endif // FLUTTER_PLUGIN_VOLUME_CONTROLLER_PLUGIN_H_
