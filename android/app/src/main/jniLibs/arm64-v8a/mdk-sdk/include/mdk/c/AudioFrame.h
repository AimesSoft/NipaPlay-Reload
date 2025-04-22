/*
 * Copyright (c) 2025 WangBin <wbsecg1 at gmail.com>
 * This file is part of MDK
 * MDK SDK: https://github.com/wang-bin/mdk-sdk
 * Free for opensource softwares or non-commercial use.
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 */
#pragma once
#include "global.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

struct mdkAudioFrame;

enum MDK_SampleFormat {
    MDK_SampleFormat_Unknown,
    MDK_SampleFormat_U8,
    MDK_SampleFormat_U8P,
    MDK_SampleFormat_S16,
    MDK_SampleFormat_S16P,
    MDK_SampleFormat_S32,
    MDK_SampleFormat_S32P,
    MDK_SampleFormat_F32,
    MDK_SampleFormat_F32P,
    MDK_SampleFormat_F64,
    MDK_SampleFormat_F64P,
};

typedef struct mdkAudioFrameAPI {
    struct mdkAudioFrame* object;

    int (*planeCount)(struct mdkAudioFrame*);
    enum MDK_SampleFormat (*sampleFormat)(struct mdkAudioFrame*);
    uint64_t (*channelMask)(struct mdkAudioFrame*);
    int (*channels)(struct mdkAudioFrame*);
    int (*sampleRate)(struct mdkAudioFrame*);
    bool (*addBuffer)(struct mdkAudioFrame*, const uint8_t* data, size_t size, int plane/* = -1*/, void* buf, void (*bufDeleter)(void** pBuf));
    void (*setBuffers)(struct mdkAudioFrame*, uint8_t const** const data, int bytesPerPlane);
    /* data size is bytesPerPlane()*/
    const uint8_t* (*bufferData)(struct mdkAudioFrame*, int plane);
    int (*bytesPerPlane)(struct mdkAudioFrame*);
    void (*setSamplesPerChannel)(struct mdkAudioFrame*, int samples);
    int (*samplesPerChannel)(struct mdkAudioFrame*);
    void (*setTimestamp)(struct mdkAudioFrame*, double t);
    double (*timestamp)(struct mdkAudioFrame*);
    double (*duration)(struct mdkAudioFrame*);

    struct mdkAudioFrameAPI* (*to)(struct mdkAudioFrame*, enum MDK_SampleFormat format, int channels, int sampleRate);
    void* reserved[8];
} mdkAudioFrameAPI;

MDK_API mdkAudioFrameAPI* mdkAudioFrameAPI_new(enum MDK_SampleFormat format, int channels, int sampleRate, int samples);
MDK_API void mdkAudioFrameAPI_delete(struct mdkAudioFrameAPI**);

#ifdef __cplusplus
}
#endif
