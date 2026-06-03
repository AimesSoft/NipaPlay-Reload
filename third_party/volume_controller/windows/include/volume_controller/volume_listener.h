#ifndef VOLUME_LISTENER_H_
#define VOLUME_LISTENER_H_

#include <windows.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <iostream>

#include "volume_callback.h"

namespace volume_listener
{
    class VolumeListener
    {
    public:
        static VolumeListener &GetInstance();

        bool Initialize();

        void Dispose();

        bool RegisterVolumeNotification(volume_callback::VolumeCallback *callback);

        void DisposeVolumeNotification();

    private:
        IAudioEndpointVolume *pVolume_ = nullptr;
        volume_callback::VolumeCallback *pCallback_ = nullptr;
    };
} // namespace volume_listener

#endif // VOLUME_LISTENER_H_