/*
 * Copyright (c) 2023-2024 WangBin <wbsecg1 at gmail.com>
 */
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <jni.h>
#include <android/native_window_jni.h>
#include <android/log.h>
//#include <vulkan/vulkan.h> // before any mdk header
#include <mdk/Player.h>
#include <mdk/MediaInfo.h>
#include <cassert>
#include <unordered_map>
#include <iostream>
#include <sys/system_properties.h>

using namespace std;

class TexturePlayer final : public mdk::Player
{
public:
    TexturePlayer(jlong handle)
        : mdk::Player(reinterpret_cast<mdkPlayerAPI*>(handle))
    {
    }

    int width = 0;
    int height = 0;
    jobject surface = nullptr;
    void* vo_opaque = nullptr; // can change by TextureRegistry.SurfaceProducer.Callback
private:
};

static unordered_map<int64_t, shared_ptr<TexturePlayer>> players;


extern "C" {

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {

    mdk::SetGlobalOption("profiler.gpu", 1);

    clog << "JNI_OnLoad" << endl;
    JNIEnv *env = nullptr;
    if (vm->GetEnv((void **) &env, JNI_VERSION_1_4) != JNI_OK || !env) {
        clog << "GetEnv for JNI_VERSION_1_4 failed" << endl;
        return -1;
    }

    mdk::SetGlobalOption("JavaVM", vm);
    mdk::SetGlobalOption("MDK_KEY", "980B9623276F746C5FBB5EC5120D4A99A0B58B635592EAEE41F6817FDF3B28B96AC4A49866257726C19B246863B5ADAF5D17464E86D72A90634E8AE8418F810967F469DCD8908B93A044A13AEDF2B566E0B5810523E2B59E2D83E616B1B807B66253E1607A79BC86AEDE1AEF46F79AA60F36BE44DDEE47B84E165AF2788F8109");
    return JNI_VERSION_1_4;
}

void JNI_OnUnload(JavaVM *vm, void *reserved) {
    clog << "JNI_OnUnload" << endl;
}
}

extern "C"
JNIEXPORT void JNICALL
Java_com_mediadevkit_fvp_FvpPlugin_nativeSetSurface(JNIEnv *env, jobject thiz, jlong player_handle,
                                                    jlong tex_id, jobject surface, jint w, jint h, jboolean tunnel) {
    if (!player_handle || !surface) {
        if (auto it = players.find(tex_id); it != players.end()) {
            auto& player = it->second;
            auto s = player->surface;
            player->updateNativeSurface(nullptr);
            players.erase(it);
            if (s) {
                env->DeleteGlobalRef(surface);
            }
        } else {
            clog << "player not found(already removed?) for textureId " + std::to_string(tex_id) + " surface " + std::to_string((intptr_t)surface) << endl;
        }
        return;
    }
    assert(surface && "null surface");
    auto player = make_shared<TexturePlayer>(player_handle);
    clog << __func__ << endl;
    if (tunnel) { // TODO: tunel via ffi + global var
        player->surface = env->NewGlobalRef(surface);
        player->setProperty("video.decoder", "surface=" + std::to_string((intptr_t)player->surface));
    } else {
        player->updateNativeSurface(surface, w, h);
        player->vo_opaque = surface;
    }
    players[tex_id] = player;
}

extern "C"
JNIEXPORT bool JNICALL
MdkIsEmulator()
{
    // run getprop to see all properties
    char v[PROP_VALUE_MAX+1];
    __system_property_get("ro.kernel.qemu", v);
    if (atoi(v) == 1)
        return true;
    __system_property_get("ro.boot.qemu", v);
    if (atoi(v) == 1)
        return true;
    __system_property_get("ro.product.board", v);
    if (strstr(v, "goldfish"))
        return true;
    __system_property_get("ro.hardware.egl", v);
    if (strstr(v, "emulation"))
        return true;
    __system_property_get("ro.hardware", v);
    if (strstr(v, "ranchu"))
        return true;
    __system_property_get("ro.build.characteristics", v);
    if (strstr(v, "emulator"))
        return true;
    return false;
}

extern "C"
JNIEXPORT void* JNICALL
MdkGetPlayerVid(int64_t tex_id)
{
    if (tex_id < 0)
        return nullptr;
    if (const auto it = players.find(tex_id); it != players.end()) {
        const auto& player = it->second;
        return player->vo_opaque;
    }
    return nullptr;
}