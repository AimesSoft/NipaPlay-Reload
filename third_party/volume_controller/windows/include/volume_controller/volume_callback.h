#ifndef VOLUME_CALLBACK_H_
#define VOLUME_CALLBACK_H_

#include <windows.h>
#include <endpointvolume.h>
#include <iostream>
#include <functional>

namespace volume_callback
{
    class VolumeCallback : public IAudioEndpointVolumeCallback
    {
    public:
        VolumeCallback(std::function<void(float)> on_volume_change)
            : refCount_(1), on_volume_change_(on_volume_change) {}

        // IUnknown methods
        ULONG STDMETHODCALLTYPE AddRef() override
        {
            return InterlockedIncrement(&refCount_);
        }

        ULONG STDMETHODCALLTYPE Release() override
        {
            ULONG ulRef = InterlockedDecrement(&refCount_);
            if (0 == ulRef)
            {
                delete this;
            }
            return ulRef;
        }

        HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, VOID **ppvInterface) override
        {
            if (IID_IUnknown == riid || __uuidof(IAudioEndpointVolumeCallback) == riid)
            {
                AddRef();
                *ppvInterface = (IAudioEndpointVolumeCallback *)this;
            }
            else
            {
                *ppvInterface = nullptr;
                return E_NOINTERFACE;
            }
            return S_OK;
        }

        // IAudioEndpointVolumeCallback method
        HRESULT STDMETHODCALLTYPE OnNotify(PAUDIO_VOLUME_NOTIFICATION_DATA pNotify) override
        {
            on_volume_change_(pNotify->fMasterVolume);
            return S_OK;
        }

    private:
        LONG refCount_;
        std::function<void(float)> on_volume_change_;
    };
} // namespace volume_callback

#endif // VOLUME_CALLBACK_H_