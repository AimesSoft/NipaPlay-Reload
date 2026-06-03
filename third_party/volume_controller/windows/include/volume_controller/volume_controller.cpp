#include "volume_controller.h"

namespace volume_controller
{
    VolumeController &VolumeController::GetInstance()
    {
        static VolumeController instance;
        return instance;
    }

    bool VolumeController::Initialize()
    {
        IMMDeviceEnumerator *pEnumerator = nullptr;
        IMMDevice *pDevice = nullptr;

        HRESULT hr = CoInitialize(nullptr);
        if (FAILED(hr))
        {
            std::cerr << "Failed to initialize COM library: " << hr << std::endl;
            return false;
        }

        hr = CoCreateInstance(
            __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
            __uuidof(IMMDeviceEnumerator), (void **)&pEnumerator);

        if (FAILED(hr))
        {
            std::cerr << "Failed to create device enumerator: " << hr << std::endl;
            CoUninitialize();
            return false;
        }

        hr = pEnumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &pDevice);
        if (FAILED(hr))
        {
            std::cerr << "Failed to get default audio endpoint: " << hr << std::endl;
            pEnumerator->Release();
            CoUninitialize();
            return false;
        }

        hr = pDevice->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr, (void **)&pVolume_);
        if (FAILED(hr))
        {
            std::cerr << "Failed to activate audio endpoint volume: " << hr << std::endl;
            pEnumerator->Release();
            pDevice->Release();
            CoUninitialize();
            return false;
        }

        pDevice->Release();
        pEnumerator->Release();

        return true;
    }

    void VolumeController::Dispose()
    {
        if (pVolume_)
            pVolume_->Release();
        CoUninitialize();
    }

    float VolumeController::GetVolume()
    {
        float currentVolume = 0.0;
        HRESULT hr = pVolume_->GetMasterVolumeLevelScalar(&currentVolume);
        if (FAILED(hr))
        {
            std::cerr << "Failed to get master volume level: " << hr << std::endl;
            return 0;
        }

        return currentVolume;
    }

    bool VolumeController::SetVolume(float volume)
    {
        HRESULT hr = pVolume_->SetMasterVolumeLevelScalar(volume, nullptr);
        if (FAILED(hr))
        {
            std::cerr << "Failed to set master volume level: " << hr << std::endl;
            return false;
        }

        return true;
    }

    bool VolumeController::IsMuted()
    {
        BOOL isMuted = FALSE;
        HRESULT hr = pVolume_->GetMute(&isMuted);
        if (FAILED(hr))
        {
            std::cerr << "Failed to get mute status: " << hr << std::endl;
            return false;
        }

        return isMuted == TRUE;
    }

    bool VolumeController::SetMute(bool isMute)
    {
        HRESULT hr = pVolume_->SetMute(isMute, nullptr);
        if (FAILED(hr))
        {
            std::cerr << "Failed to set mute status: " << hr << std::endl;
            return false;
        }

        return true;
    }
}