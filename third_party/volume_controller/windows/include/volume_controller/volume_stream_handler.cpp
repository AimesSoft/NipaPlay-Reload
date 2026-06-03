#include "volume_stream_handler.h"

namespace volume_stream_handler
{
    // VolumeStreamHandler::VolumeStreamHandler() : volume_listener_(volume_listener::VolumeListener::GetInstance())
    VolumeStreamHandler::VolumeStreamHandler() : volume_listener_(volume_listener::VolumeListener::GetInstance())
    {
        volume_listener_.Initialize();
    }

    VolumeStreamHandler::~VolumeStreamHandler()
    {
        volume_listener_.Dispose();
    }

    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> VolumeStreamHandler::OnListenInternal(
        const flutter::EncodableValue *arguments,
        std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events)
    {
        const flutter::EncodableMap *args_map = std::get_if<flutter::EncodableMap>(arguments);
        const bool *fetchInitialVolume = std::get_if<bool>(GetArgValue(*args_map, constants::EventArgument::fetchInitialVolume));

        event_sink_ = std::move(events);

        auto callback = new volume_callback::VolumeCallback([this](float volume)
                                                            { SendVolumeChangeEvent(volume); });

        volume_listener_.RegisterVolumeNotification(callback);

        if (fetchInitialVolume && *fetchInitialVolume)
        {
            float volume = volume_controller::VolumeController::GetInstance().GetVolume();

            // Send the initial volume
            event_sink_->Success(flutter::EncodableValue(volume));
        }

        return nullptr;
    }

    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> VolumeStreamHandler::OnCancelInternal(
        const flutter::EncodableValue *arguments)
    {
        event_sink_ = nullptr;
        return nullptr;
    }

    void VolumeStreamHandler::SendVolumeChangeEvent(float volume)
    {
        if (event_sink_)
        {
            event_sink_->Success(flutter::EncodableValue(volume));
        }
    }
}