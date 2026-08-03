/*
 * Copyright (c) 2023 WangBin <wbsecg1 at gmail.com>
 */
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include "fvp_plugin.h"
#include <flutter/standard_method_codec.h>

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d11.lib")

using namespace std;

#define MS_ENSURE(f, ...) MS_CHECK(f, return __VA_ARGS__;)
#define MS_WARN(f) MS_CHECK(f)
#define MS_CHECK(f, ...)  do { \
        while (FAILED(GetLastError())) {} \
        HRESULT __ms_hr__ = (f); \
        if (FAILED(__ms_hr__)) { \
            std::clog << #f "  ERROR@" << __LINE__ << __FUNCTION__ << ": (" << std::hex << __ms_hr__ << std::dec << ") " << std::error_code(__ms_hr__, std::system_category()).message() << std::endl << std::flush; \
            __VA_ARGS__ \
        } \
    } while (false)


namespace fvp {

class TexturePlayer final: public Player
{
public:
    TexturePlayer(int64_t handle, const ComPtr<ID3D11Texture2D>& d3d11tex, flutter::TextureRegistrar* texRegistrar)
        : Player(reinterpret_cast<mdkPlayerAPI*>(handle))
        , rt(d3d11tex)
    {
        ComPtr<ID3D11Device> dev;
        rt->GetDevice(&dev);
        dev->GetImmediateContext(&ctx);

        D3D11_TEXTURE2D_DESC desc;
        rt->GetDesc(&desc);
        desc.MiscFlags |= D3D11_RESOURCE_MISC_SHARED;
        MS_ENSURE(dev->CreateTexture2D(&desc, nullptr, &tex));

        ComPtr<IDXGIResource> res;
        MS_ENSURE(tex.As(&res));
        HANDLE shared_handle = nullptr;
        MS_ENSURE(res->GetSharedHandle(&shared_handle));
        flt_surface_desc->struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
        flt_surface_desc->handle = shared_handle;// tex.Get();
        //flt_surface_desc->handle = tex.Get(); // eglbind error
        flt_surface_desc->width = flt_surface_desc->visible_width = desc.Width;
        flt_surface_desc->height = flt_surface_desc->visible_height = desc.Height;
        flt_surface_desc->release_context = nullptr;
        flt_surface_desc->release_callback = [](void* release_context) {};
        //flt_surface_desc->format = kFlutterDesktopPixelFormatBGRA8888;
        flt_tex = make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
            kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle
            //kFlutterDesktopGpuSurfaceTypeD3d11Texture2D
            , [pflt_surface_desc = flt_surface_desc.get(), this](size_t width, size_t height) {
                //printf("ObtainDescriptorCallback %llux%llu. shared_handle_ %p\n", width, height, shared_handle_); fflush(nullptr);
                //player.renderVideo(); // stutter
                scoped_lock lock(mtx);
                ctx->CopyResource(tex.Get(), rt.Get());
                ctx->Flush();
                return pflt_surface_desc;
            }));
        textureId = texRegistrar->RegisterTexture(flt_tex.get());


        D3D11RenderAPI ra{};
        ra.rtv = rt.Get();
        setRenderAPI(&ra);
        setVideoSurfaceSize(desc.Width, desc.Height);
        setRenderCallback([this, texRegistrar](void*) {
            scoped_lock lock(mtx);
            renderVideo();
            texRegistrar->MarkTextureFrameAvailable(textureId);
            });

    }

    ~TexturePlayer() override {
        setRenderCallback(nullptr);
        setVideoSurfaceSize(-1, -1);
    }

    int64_t textureId;

private:
    unique_ptr<flutter::TextureVariant> flt_tex;
    unique_ptr<FlutterDesktopGpuSurfaceDescriptor> flt_surface_desc = make_unique<FlutterDesktopGpuSurfaceDescriptor>();
    ComPtr<ID3D11Texture2D> tex;
    ComPtr<ID3D11Texture2D> rt;
    ComPtr<ID3D11DeviceContext> ctx;
    mutex mtx;
};

template<typename T>
auto View_GetGraphicsAdapter(T* v) -> decltype(v->GetGraphicsAdapter())
{
    return v->GetGraphicsAdapter();
}

template<typename T>
IDXGIAdapter* View_GetGraphicsAdapter(T v) {
    return nullptr;
}

// static
void FvpPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  IDXGIAdapter *adapter = View_GetGraphicsAdapter(registrar->GetView());
  if (!adapter)
    clog << "FlutterView::GetGraphicsAdapter() is not available, texture may be invisible" << endl;
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "fvp",
          &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<FvpPlugin>(registrar->texture_registrar(), adapter);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
  SetGlobalOption("MDK_KEY", "980B9623276F746C5FBB5EC5120D4A99A0B58B635592EAEE41F6817FDF3B28B96AC4A49866257726C19B246863B5ADAF5D17464E86D72A90634E8AE8418F810967F469DCD8908B93A044A13AEDF2B566E0B5810523E2B59E2D83E616B1B807B66253E1607A79BC86AEDE1AEF46F79AA60F36BE44DDEE47B84E165AF2788F8109");
}

FvpPlugin::FvpPlugin(flutter::TextureRegistrar* tr, IDXGIAdapter* adapter)
    : texture_registrar_(tr)
    , adapter_(adapter)
{}

FvpPlugin::~FvpPlugin() {}

void FvpPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "CreateRT") {
      auto args = std::get<flutter::EncodableMap>(*method_call.arguments());
      const auto width = (UINT)args[flutter::EncodableValue("width")].LongValue();
      const auto height = (UINT)args[flutter::EncodableValue("height")].LongValue();

      MS_WARN(D3D11CreateDevice(adapter_.Get(), adapter_ ? D3D_DRIVER_TYPE_UNKNOWN : D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0, D3D11_SDK_VERSION, &dev_, nullptr, &ctx_));
      if (!dev_) {
          result->Error("device", "create device failed");
          return;
      }
      ComPtr<ID3D10Multithread> mt;
      if (SUCCEEDED(dev_.As(&mt)))
          mt->SetMultithreadProtected(TRUE);
      D3D11_TEXTURE2D_DESC desc{
        .Width = width,
        .Height = height,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = DXGI_FORMAT_B8G8R8A8_UNORM, // rgba eglbind error
        .SampleDesc = {
            .Count = 1,
        },
        .Usage = D3D11_USAGE_DEFAULT,
        .BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE,
        .MiscFlags = D3D11_RESOURCE_MISC_SHARED,// | D3D11_RESOURCE_MISC_SHARED_NTHANDLE
      };

      ComPtr<ID3D11Texture2D> tex;
      MS_WARN(dev_->CreateTexture2D(&desc, nullptr, &tex));
      if (!tex) {
          result->Success();
          return;
      }

      const auto handle = args[flutter::EncodableValue("player")].LongValue();
      auto player = make_shared<TexturePlayer>(handle, tex, texture_registrar_);
      result->Success(flutter::EncodableValue(player->textureId));
      players_[player->textureId] = player;
  } else if (method_call.method_name() == "ReleaseRT") {
    auto args = std::get<flutter::EncodableMap>(*method_call.arguments());
    const auto texId = args[flutter::EncodableValue("texture")].LongValue();
    texture_registrar_->UnregisterTexture(texId);
    if (auto it = players_.find(texId); it != players_.cend()) {
        players_.erase(it);
    }
    result->Success();
  } else if (method_call.method_name() == "MixWithOthers") {
    result->Success();
  } else {
    result->NotImplemented();
  }
}

}  // namespace fvp
