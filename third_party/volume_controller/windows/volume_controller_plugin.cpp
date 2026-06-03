#include "volume_controller_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <sstream>

namespace volume_controller
{
  VolumeControllerPlugin::VolumeControllerPlugin() : volume_controller_(VolumeController::GetInstance())
  {
    volume_controller_.Initialize();
  }

  VolumeControllerPlugin::~VolumeControllerPlugin()
  {
    volume_controller_.Dispose();
  }

  // static
  void VolumeControllerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto plugin = std::make_unique<VolumeControllerPlugin>();

    auto method_channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), constants::ChannelName::methodChannel,
            &flutter::StandardMethodCodec::GetInstance());

    auto event_channel =
        std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
            registrar->messenger(), constants::ChannelName::eventChannel,
            &flutter::StandardMethodCodec::GetInstance());

    // Register the method channel
    method_channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    // Register the event channel
    event_channel->SetStreamHandler(std::make_unique<volume_stream_handler::VolumeStreamHandler>());

    // Set the channel to the plugin
    registrar->AddPlugin(std::move(plugin));
  }

  void VolumeControllerPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    const std::string &method_name = method_call.method_name();

    if (method_name == constants::MethodName::getVolume)
    {
      result->Success(flutter::EncodableValue(volume_controller_.GetVolume()));
    }
    else if (method_name == constants::MethodName::setVolume)
    {
      const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      const double *volume = std::get_if<double>(GetArgValue(*arguments, constants::MethodArgument::volume));

      if (!volume)
      {
        result->Error("InvalidArguments", "Volume argument is missing");
        return;
      }

      // Set the volume
      bool success = volume_controller_.SetVolume(static_cast<float>(*volume));
      if (!success)
      {
        result->Error("SetVolumeError", "Failed to set volume");
        return;
      }

      result->Success();
    }
    else if (method_name == constants::MethodName::isMuted)
    {
      result->Success(flutter::EncodableValue(volume_controller_.IsMuted()));
    }
    else if (method_call.method_name().compare(constants::MethodName::setMute) == 0)
    {
      const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      const bool *isMute = std::get_if<bool>(GetArgValue(*arguments, constants::MethodArgument::isMute));

      if (!isMute)
      {
        result->Error("InvalidArguments", "isMute argument is missing");
        return;
      }

      // Set the mute
      bool success = volume_controller_.SetMute(*isMute);
      if (!success)
      {
        result->Error("SetMuteError", "Failed to set mute");
        return;
      }

      result->Success();
    }
    else
    {
      result->NotImplemented();
    }
  }

} // namespace volume_controller