#ifndef VOLUME_CONTROLLER_H_
#define VOLUME_CONTROLLER_H_

#include <windows.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <iostream>

namespace volume_controller
{
    class VolumeController
    {
    public:
        static VolumeController &GetInstance();

        bool Initialize();

        void Dispose();

        float GetVolume();

        bool SetVolume(float volume);

        bool IsMuted();

        bool SetMute(bool isMute);

    private:
        VolumeController() = default;
        ~VolumeController() = default;

        VolumeController(const VolumeController &) = delete;
        VolumeController &operator=(const VolumeController &) = delete;

        IAudioEndpointVolume *pVolume_ = nullptr;
    };
}

#endif // VOLUME_CONTROLLER_H_