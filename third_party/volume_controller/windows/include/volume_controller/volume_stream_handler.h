#ifndef VOLUME_STREAM_HANDLER_H_
#define VOLUME_STREAM_HANDLER_H_

#include <flutter/event_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <mutex>

#include "constants.h"
#include "volume_listener.h"
#include "volume_controller.h"
#include "helper.h"

namespace volume_stream_handler
{
    class VolumeStreamHandler : public flutter::StreamHandler<flutter::EncodableValue>
    {
    public:
        VolumeStreamHandler();
        ~VolumeStreamHandler();

        void SendVolumeChangeEvent(float volume);

    protected:
        std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
            const flutter::EncodableValue *arguments,
            std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events) override;

        std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(
            const flutter::EncodableValue *arguments) override;

    private:
        std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
        volume_listener::VolumeListener &volume_listener_;
    };
}

#endif // VOLUME_STREAM_HANDLER_H_