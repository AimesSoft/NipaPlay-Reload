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
#include "c/AudioFrame.h"
#include <algorithm>

MDK_NS_BEGIN

enum class SampleFormat
{
    Unknown = 0,
    U8,
    U8P,
    S16,
    S16P,
    S32,
    S32P,
    F32,
    F32P,
    F64,
    F64P,
};

static inline bool operator!(SampleFormat f) { return f == SampleFormat::Unknown; }

class AudioFrame
{
public:
    AudioFrame(const AudioFrame&) = delete;
    AudioFrame& operator=(const AudioFrame&) = delete;
    AudioFrame(AudioFrame&& that) {
        std::swap(p, that.p);
        std::swap(owner_, that.owner_);
    }
    AudioFrame& operator=(AudioFrame&& that)  {
        std::swap(p, that.p);
        std::swap(owner_, that.owner_);
        return *this;
    }

    AudioFrame() = default;
/*!
  \brief AudioFrame
  Construct a frame for given format, size. If strides is not null, a single contiguous memory for all planes will be allocated.
  If data is not null, data is copied to allocated memory.
  \param samples samples per channel, can be 0, then you have to call addBuffer() to add data
  \sa setBuffers
   NOTE: Unkine setBuffers(), no memory is allocated for null strides.
 */
    AudioFrame(SampleFormat format, int channels, int sampleRate, int samplesPerChannel) {
        p = mdkAudioFrameAPI_new(MDK_SampleFormat(format), channels, sampleRate, samplesPerChannel);
    }

    AudioFrame(mdkAudioFrameAPI* pp) : p(pp) {}

    ~AudioFrame() {
        if (owner_)
            mdkAudioFrameAPI_delete(&p);
    }

// isValid() is true for EOS frame, but no data and timestamp() is TimestampEOS.
    bool isValid() const { return !!p; }
    explicit operator bool() const { return isValid();}

    void attach(mdkAudioFrameAPI* api) {
        if (owner_)
            mdkAudioFrameAPI_delete(&p);
        p = api;
        owner_ = false;
    }

    mdkAudioFrameAPI* detach() {
        auto ptr = p;
        p = nullptr;
        return ptr;
    }

    mdkAudioFrameAPI* toC() const {
        return p;
    }

    int planeCount() const { return MDK_CALL(p, planeCount); }

    SampleFormat format() const {
        return (SampleFormat)MDK_CALL(p, sampleFormat);
    }

    int sampleRate() const {
        return MDK_CALL(p, sampleRate);
    }

    int channels() const {
        return MDK_CALL(p, channels);
    }

    uint64_t channelMask() const {
        return MDK_CALL(p, channelMask);
    }

    int samplesPerChannel() const {
        return MDK_CALL(p, samplesPerChannel);
    }
/*!
  \brief addBuffer
  Add an external buffer to nth plane, store external buffer data ptr. The old buffer will be released.
  \param data external buffer data ptr
  \param size
  \param buf external buffer ptr. user should ensure the buffer is alive before frame is destroyed.
  \param bufDeleter to delete buf when frame is destroyed
  If both buf and bufDeleter are null, data is copied
 */
    bool addBuffer(const uint8_t* data, int size, int plane = -1, void* buf = nullptr, void (*bufDeleter)(void** pBuf) = nullptr) {
        return MDK_CALL(p, addBuffer, data, size, plane, buf, bufDeleter);
    }

/*!
   \brief setBuffers
   Add buffers with data copied from given source. a single contiguous memory for all planes is always allocated.
   If data is not null, data is copied to allocated memory.
   \param data array of source data planes, array size MUST >= plane count of format if not null. Can be null and allocate memory without copying.
   \param bytesPerPlane if 0, compute from format
   NOTE: data[i] will be filled with allocated plane address if necessary(data != null).
   If data[0] != null but data[i] == null, assume copying from contiguous source data.
 */
    void setBuffers(uint8_t const** const data, int bytesPerPlane) {
        MDK_CALL(p, setBuffers, data, bytesPerPlane);
    }

    const uint8_t* bufferData(int plane = 0) const {
        return MDK_CALL(p, bufferData, plane);
    }

    int bytesPerPlane() const {
        return MDK_CALL(p, bytesPerPlane);
    }

    void setTimestamp(double t) {
        return MDK_CALL(p, setTimestamp, t);
    }

    double timestamp() const {
        if (!p)
            return -1;
        return MDK_CALL(p, timestamp);
    }

    double duration() const {
        return MDK_CALL(p, duration);
    }
/*!
  \brief to
  The result frame data is always on host memory. If it's already on host memory and the same as target format, return the current frame.
  NOTE: compressed input/output formats are not supported
  \param fmt output format. if invalid, same as format()
  if all output parameters(invalid) are the same as input, return self
  \return Invalid frame if failed
 */
    AudioFrame to(SampleFormat format, int channels, int sampleRate) {
        if (!p)
            return AudioFrame(format, channels, sampleRate, 0);
        return AudioFrame(MDK_CALL(p, to, MDK_SampleFormat(format), channels, sampleRate));
    }
private:
    mdkAudioFrameAPI* p = nullptr;
    bool owner_ = true;
};

MDK_NS_END