/*
 * Copyright (c) 2026 WangBin <wbsecg1 at gmail.com>
 */
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include "include/fvp/fvp_plugin.h"
#include <napi/native_api.h>
#include <native_window/external_window.h>
#include <rawfile/raw_file_manager.h>
#include <mdk/c/Player.h>
#include <mdk/c/global.h>
#include <iostream>
#include <unordered_map>

using namespace std;

struct TexturePlayer {
    // Dart owns this player. Even a non-owning mdk::Player wrapper calls
    // mdkPlayerAPI_reset on destruction, resetting a newly prepared video
    // when its previous texture is released during reopen.
    const mdkPlayerAPI* api = nullptr;
    int width = 0;
    int height = 0;
    OHNativeWindow* window = nullptr;
};

static unordered_map<int64_t, shared_ptr<TexturePlayer>> players;

// nativeSetSurface(playerHandle: number, texId: number, surfaceId: number, w: number, h: number): void
static napi_value NativeSetSurface(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t playerHandle = 0;
    napi_get_value_int64(env, args[0], &playerHandle);

    int64_t texId = 0;
    napi_get_value_int64(env, args[1], &texId);

    int64_t surfaceId = 0;
    napi_get_value_int64(env, args[2], &surfaceId);

    int32_t w = 0, h = 0;
    napi_get_value_int32(env, args[3], &w);
    napi_get_value_int32(env, args[4], &h);

    if (!playerHandle || !surfaceId) {
        if (auto it = players.find(texId); it != players.end()) {
            auto& player = it->second;
            player->api->updateNativeSurface(
                player->api->object, nullptr, -1, -1, MDK_SurfaceType_Auto);
            if (player->window) {
                OH_NativeWindow_DestroyNativeWindow(player->window);
                player->window = nullptr;
            }
            players.erase(it);
        } else {
            clog << "FvpPlugin: player not found (already removed?) for texId " << texId << endl;
        }
        return nullptr;
    }

    OHNativeWindow* window = nullptr;
    int32_t ret = OH_NativeWindow_CreateNativeWindowFromSurfaceId(static_cast<uint64_t>(surfaceId), &window);
    if (ret != 0 || !window) {
        clog << "FvpPlugin: OH_NativeWindow_CreateNativeWindowFromSurfaceId failed: " << ret << endl;
        return nullptr;
    }

    auto player = make_shared<TexturePlayer>();
    player->api = reinterpret_cast<const mdkPlayerAPI*>(playerHandle);
    player->width = w;
    player->height = h;
    player->window = window;
    player->api->updateNativeSurface(
        player->api->object, window, w, h, MDK_SurfaceType_Auto);
    players[texId] = player;

    return nullptr;
}

// nativeSetResourceManager(resourceManager: object): void
// Converts an OHOS ResourceManager object to native pointer and passes it to MDK.
static napi_value NativeSetResourceManager(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    NativeResourceManager* nativeRm = OH_ResourceManager_InitNativeResourceManager(env, args[0]);
    if (nativeRm) {
        MDK_setGlobalOptionPtr("resourceManager", nativeRm);
    }
    return nullptr;
}

static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "nativeSetSurface", nullptr, NativeSetSurface, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeSetResourceManager", nullptr, NativeSetResourceManager, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

    return exports;
}

NAPI_MODULE(fvp, Init)

extern "C" bool MdkIsEmulator()
{
    return false;
}

extern "C" void* MdkGetPlayerVid(int64_t tex_id)
{
    if (tex_id < 0)
        return nullptr;
    if (const auto it = players.find(tex_id); it != players.end()) {
        return it->second->window;
    }
    return nullptr;
}
