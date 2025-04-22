/*
 * Copyright (c) 2019-2025 WangBin <wbsecg1 at gmail.com>
 * This file is part of MDK
 * MDK SDK: https://github.com/wang-bin/mdk-sdk
 * Free for opensource softwares or non-commercial use.
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 */
#pragma once
#include "global.h"
#include "MediaInfo.h"
#include "RenderAPI.h"
#include "c/Player.h"
#include "AudioFrame.h"
#include "VideoFrame.h"
#include <cinttypes>
#include <cstdlib>
#include <map>
#include <mutex>
#include <set>
#include <vector>

MDK_NS_BEGIN

/*!
  \brief PrepareCallback
  \param position in callback is the timestamp of the 1st frame(video if exists) after seek, or <0 (TODO: error code as position) if prepare() failed.
  \param boost in callback can be set by user(*boost = true/false) to boost the first frame rendering. default is true.
  \return false to unload media immediately when media is loaded and MediaInfo is ready, true to continue.
    example: always return false can be used as media information reader
 */
using PrepareCallback = std::function<bool(int64_t position, bool* boost)>;

/*!
 * \brief The Player class
 * High level API with basic playback function.
 */
class AudioFrame;
class VideoFrame;
class Player
{
public:
/*!
  \brief foreignGLContextDestroyed()
  Release GL resources bound to the context.
  - MUST be called when a foreign OpenGL context previously used is being destroyed and player object is already destroyed. The context MUST be current.
  - If player object is still alive, setVideoSurfaceSize(-1, -1, ...) is preferred.
  - If forget to call both foreignGLContextDestroyed() and setVideoSurfaceSize(-1, -1, ...) in the context, resources will be released in the next draw in the same context.
     But the context may be destroyed later, then resource will never be released
*/
    static void foreignGLContextDestroyed() {
        MDK_foreignGLContextDestroyed();
    }

    Player(const Player&) = delete;
    Player& operator=(const Player&) = delete;
    Player(const mdkPlayerAPI* cp = nullptr)
        : p(cp)
        , owner_(!cp) {
        if (!p)
            p = mdkPlayerAPI_new();
    }
    virtual ~Player() {
        mdkPlayerAPI_reset(&p, owner_);
    }

    void setMute(bool value = true) {
        MDK_CALL(p, setMute, value);
        mute_ = value;
    }

    bool isMute() const { return mute_; }
/*!
  \brief setVolume
  Set audio volume level
  \param value linear volume level, range is >=0. 1.0 is source volume
  \param channel channel number, int value of AudioFormat::Channel, -1 for all channels.
  The same as ms log2(SpeakerPosition), see https://docs.microsoft.com/en-us/windows-hardware/drivers/ddi/ksmedia/ns-ksmedia-ksaudio_channel_config#remarks
  setVolume(value, -1) equals to setVolume(value)
 */
    void setVolume(float value) {
        MDK_CALL(p, setVolume, value);
        volume_ = value;
    }
    void setVolume(float value, int channel) {
        MDK_CALL(p, setChannelVolume, value, channel);
    }

    float volume() const { return volume_; }
/*!
  \brief setFrameRate
  Set frame rate, frames per seconds
  \param value frame rate
  - 0 (default): use frame timestamp, or default frame rate 25.0fps if stream has no timestamp
  - <0: render ASAP.
  - >0: target frame rate
 */
    void setFrameRate(float value) {
        MDK_CALL(p, setFrameRate, value);
    }
/*!
  \brief setMedia
  Set a new media url.  If url changed, will stop current playback, and reset active tracks, external tracks set by setMedia(url, type)
  // MUST call setActiveTracks() after setMedia(), otherwise the 1st track in the media is used
 */
    void setMedia(const char* url) {
        MDK_CALL(p, setMedia, url);
    }
/*!
  \brief
Set an individual source as track of `type`, e.g. audio track file, external subtile file. **MUST** be after main media `setMedia(url)`.
If url is empty, use `type` tracks in MediaType::Video url.
The url can contains other track types, e.g. you can load an external audio/subtitle track from a video file, and use `setActiveTracks()` to select a track.
> Note: because of filesystem restrictions on some platforms(iOS, macOS, uwp), and unable to access files in a sandbox, so you have to load subtitle files manually yourself via this function.

examples:
- set subtitle file: `setMedia("name.ass", MediaType::Subtitle)`
  TODO: default type is Unknown
*/
    void setMedia(const char* url, MediaType type) {
        MDK_CALL(p, setMediaForType, url, (MDK_MediaType)type);
    }

    const char* url() const {
        return MDK_CALL(p, url);
    }
/*!
  \brief appendBuffer
  iff media url is "stream:"
  setTimeout can abort current stream playback
*/
    bool appendBuffer(const uint8_t* data, size_t size, int options = 0) {
        return MDK_CALL(p, appendBuffer, data, size, options);
    }

    void setPreloadImmediately(bool value = true) {
        MDK_CALL(p, setPreloadImmediately, value);
    }
/*!
  \brief setNextMedia
  Gapless play the next media after current media playback end
  \param flags seek flags if startPosition > 0, accurate or fast
  set(State::Stopped) only stops current media. Call setNextMedia(nullptr, -1) first to disable next media.
  Usually you can call `currentMediaChanged()` to set a callback which invokes `setNextMedia()`, then call `setMedia()`.
*/
    void setNextMedia(const char* url, int64_t startPosition = 0, SeekFlag flags = SeekFlag::FromStart) {
        MDK_CALL(p, setNextMedia, url, startPosition, MDKSeekFlag(flags));
    }
/*!
  \brief currentMediaChanged
  Set a callback which is invoked when current media is stopped and a new media is about to play, or when setMedia() is called.
  Call before setMedia() to take effect.
 */
    void currentMediaChanged(const std::function<void()>& cb) { // call before setMedia()
        {
            const std::lock_guard<std::mutex> lock(current_mtx_);
            current_cb_ = cb;
        }
        mdkCurrentMediaChangedCallback callback;
        callback.cb = [](void* opaque){
            auto p = (Player*)opaque;
            const std::lock_guard<std::mutex> lock(p->current_mtx_);
            if (p->current_cb_) // can be null if reset cb when executing callback.cb and before executing p->xxx_cb_
                p->current_cb_();
        };
        callback.opaque = current_cb_ ? this : nullptr;
        MDK_CALL(p, currentMediaChanged, callback);
    }
/*!
  \brief setActiveTracks
  \param type if type is MediaType::Unknown, select a program(usually for mpeg ts streams). must contains only 1 value, N, indicates using the Nth program's audio and video tracks.
  Otherwise, select a set of tracks of given type.
  \param tracks set of active track number, from 0~N. Invalid track numbers will be ignored
 */
    void setActiveTracks(MediaType type, const std::set<int>& tracks) {
        std::vector<int> ts(tracks.cbegin(), tracks.cend());
        MDK_CALL(p, setActiveTracks, MDK_MediaType(type), ts.data(), ts.size());
    }
    // backends can be: AudioQueue(Apple only), OpenSL, AudioTrack(Android only), ALSA(linux only), XAudio2(Windows only), OpenAL
    void setAudioBackends(const std::vector<std::string>& names) {
        std::vector<const char*> s(names.size() + 1, nullptr);
        for (size_t i = 0; i < names.size(); ++i)
            s[i] = names[i].data();
        MDK_CALL(p, setAudioBackends, s.data());
    }

// see https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-setdecodersmediatype-type-const-stdvectorstdstring-names
    void setDecoders(MediaType type, const std::vector<std::string>& names) {
        std::vector<const char*> s(names.size() + 1, nullptr);
        for (size_t i = 0; i < names.size(); ++i)
            s[i] = names[i].data();
        MDK_CALL(p, setDecoders, MDK_MediaType(type), s.data());
    }

/*!
  \brief setTimeout
  callback ms: elapsed milliseconds
  callback return: true to abort current operation on timeout.
  A null callback can abort current operation.
  Negative timeout infinit.
  Default timeout is 10s
 */
    void setTimeout(int64_t ms, const std::function<bool(int64_t ms)>& cb = nullptr) {
        {
            const std::lock_guard<std::mutex> lock(timeout_mtx_);
            timeout_cb_ = cb;
        }
        mdkTimeoutCallback callback;
        callback.cb = [](int64_t ms, void* opaque){
            auto p = (Player*)opaque;
            const std::lock_guard<std::mutex> lock(p->timeout_mtx_);
            if (p->timeout_cb_)
                return p->timeout_cb_(ms);
            return true;
        };
        callback.opaque = timeout_cb_ ? this : nullptr;
        MDK_CALL(p, setTimeout, ms, callback);
    }

/*!
  \brief prepare
  Preload a media and then becomes State::Paused. \sa PrepareCallback
  To play a media from a given position, call prepare(ms) then set(State::Playing)
  Must ensure playback is stopped before prepare() or new media set(State::Player): set(State::Stopped) + waitFor(State::Stopped) + prepare()
  \param startPosition start from position, relative to media start position(i.e. MediaInfo.start_time)
  \param cb if startPosition > 0, same as callback of seek(), called after the first frame is decoded or load/seek/decode error. If startPosition == 0, called when media is loaded and mediaInfo is ready or load error.
  \param flags seek flag if startPosition != 0.
  For fast seek(has flag SeekFlag::Fast), the first frame is a key frame whose timestamp >= startPosition
  For accurate seek(no flag SeekFlag::Fast), the first frame is the nearest frame whose timestamp <= startPosition, but the position passed to callback is the key frame position <= startPosition
 */
    void prepare(int64_t startPosition = 0, const PrepareCallback& cb = nullptr, SeekFlag flags = SeekFlag::FromStart) {
        PrepareCallback* f = cb ? new PrepareCallback(cb) : nullptr;
        mdkPrepareCallback callback;
        callback.cb = [](int64_t position, bool* boost, void* opaque){
            auto f = (PrepareCallback*)opaque;
            auto ret = true;
            if (f)
                ret = (*f)(position, boost);
            delete f;
            return ret;
        };
        callback.opaque = f;
        MDK_CALL(p, prepare, startPosition, callback, MDKSeekFlag(flags));
    }
/*!
  \brief mediaInfo
  Current MediaInfo. You can call it in prepare() callback which is called when loaded or load failed.
  Some fields can change during playback, e.g. video frame size change(via MediaEvent), live stream duration change, realtime bitrate change.
  You may get an invalid value if mediaInfo() is called immediately after `set(State::Playing)` or `prepare()` because media is still opening but not loaded , i.e. mediaStatus() has no MediaStatus::Loaded flag.
  A live stream's duration is 0 in prepare() callback or when MediaStatus::Loaded is added, then duration increases current read duration.
*/
    const MediaInfo& mediaInfo() const {
        from_c(MDK_CALL(p, mediaInfo), &info_);
        return info_;
    }

/*!
  \brief set(State)
  Request a new state. It's async and may take effect later.
  set(State::Stopped) only stops current media. Call setNextMedia(nullptr, -1) before stop to disable next media.
  set(State::Stopped) will release all resouces and clear video renderer viewport. While a normal playback end will keep renderer resources
  and the last video frame. Manually call set(State::Stopped) to clear them.
  NOTE: the requested state is not queued. so set one state immediately after another may have no effect.
  e.g. State::Playing after State::Stopped may have no effect if playback have not been stopped and still in Playing state
  so the final state is State::Stopped. Current solution is waitFor(State::Stopped) before set(State::Playing).
  Usually no waitFor(State::Playing) because we want async load
*/
    Player& set(State value) {
        MDK_CALL(p, setState, MDK_State(value));
        return *this;
    }

    PlaybackState state() const {
        return (PlaybackState)MDK_CALL(p, state);
    }

    Player& onStateChanged(const std::function<void(State)>& cb) {
        {
            const std::lock_guard<std::mutex> lock(state_mtx_);
            state_cb_ = cb;
        }
        mdkStateChangedCallback callback;
        callback.cb = [](MDK_State value, void* opaque){
            auto p = (Player*)opaque;
            const std::lock_guard<std::mutex> lock(p->state_mtx_);
            if (p->state_cb_) {
               p->state_cb_(State(value));
            }
        };
        callback.opaque = state_cb_ ? this : nullptr;
        MDK_CALL(p, onStateChanged, callback);
        return *this;
    }
/*!
  \brief waitFor
  If failed to open a media, e.g. invalid media, unsupported format, waitFor() will finish without state change
*/
    bool waitFor(State value, long timeout = -1) {
        return MDK_CALL(p, waitFor, (MDK_State)value, timeout);
    }

    MediaStatus mediaStatus() const {
        return (MediaStatus)MDK_CALL(p, mediaStatus);
    }
/*!
  \brief onMediaStatusChanged
  Add a callback to be invoked when MediaStatus is changed
  \param cb null to clear callbacks. return true
 */

#if (__cpp_attributes+0)
//[[deprecated("use 'onMediaStatus' instead")]]
#endif
    Player& onMediaStatusChanged(const std::function<bool(MediaStatus)>& cb) {
        if (!cb)
            return onMediaStatus(nullptr);
        return onMediaStatus([cb](MediaStatus, MediaStatus newValue){
            return cb(newValue);
        });
    }

    Player& onMediaStatus(const std::function<bool(MediaStatus oldValue, MediaStatus newValue)>& cb, CallbackToken* token = nullptr) {
        mdkMediaStatusCallback callback{};
        const std::lock_guard<std::mutex> lock(status_mtx_);
        if (!cb) {
            MDK_CALL(p, onMediaStatus, callback, token ? &status_cb_key_[*token] : nullptr);
            if (token) {
                status_cb_.erase(*token);
                status_cb_key_.erase(*token);
            } else {
                status_cb_.clear();
                status_cb_key_.clear();
            }
        } else {
            static CallbackToken k = 1;
            status_cb_[k] = cb;
            callback.cb = [](MDK_MediaStatus oldValue, MDK_MediaStatus newValue, void* opaque){
                auto f = (std::function<bool(MediaStatus, MediaStatus)>*)opaque; // FIXME: erased
                return (*f)(MediaStatus(oldValue), MediaStatus(newValue));
            };
            callback.opaque = &status_cb_[k]; // add/del/invoke callback(s) via c api onMediaStatus() is thread safe and can ensure address of callback is valid
            CallbackToken t;
            MDK_CALL(p, onMediaStatus, callback, &t);
            status_cb_key_[k] = t;
            if (token)
                *token = t;
            k++;
        }
        return *this;
    }

    enum SurfaceType {
        Auto, // platform default type
        X11,
        GBM,
        Wayland,
    };
/*!
 * \brief updateNativeSurface
 * If surface is not created, create rendering context internally by createSurface() and attached to native surface
 * native surface MUST be not null before destroying player
 */
// type: ignored if win ptr does not change (request to resize)
    void updateNativeSurface(void* surface, int width = -1, int height = -1, SurfaceType type = SurfaceType::Auto) {
        MDK_CALL(p, updateNativeSurface, surface, width, height, (MDK_SurfaceType)type);
    }

    void createSurface(void* nativeHandle = nullptr, SurfaceType type = SurfaceType::Auto) {
        MDK_CALL(p, createSurface, nativeHandle, (MDK_SurfaceType)type);
    }

    void resizeSurface(int w, int h) {
        MDK_CALL(p, resizeSurface, w, h);
    }

    void showSurface() {
        MDK_CALL(p, showSurface);
    }

// vo_opaque: a ptr to identify the renderer. can be null, then it is the default vo/renderer.
    struct SnapshotRequest {
/* data: rgba or bgra data. Created internally or provided by user.
   If data is provided by user, stride,  height and width MUST be also set, and data MUST be valid until snapshot callback is finished.
 */
        uint8_t* data = nullptr;
        // result width of snapshot image set by user, or the same as current frame width if 0. no renderer transform.
        // if both requested width and height are < 0, then result image is scaled image of current frame with ratio=width/height. no renderer transform.
        // if only one of width and height < 0, then the result size is video renderer viewport size, and all transforms will be applied.
        // if both width and height == 0, then result size is region of interest size of video frame set by setPointMap(), or video frame size
        int width = 0;
        int height = 0;
        int stride = 0;
        bool subtitle = false; // not supported yet
    };
/* \brief SnapshotCallback
   snapshot callback.
   \param req result request. If null, snapshot failed. Otherwise req.width, height and stride are always >0, data is never null.
   \param opaque user data
   \returns a file path to save as a file(jpeg is recommended, other formats depends on ffmpeg runtime). or empty to do nothing.
   Returned string will be freed internally(assume allocated by malloc family apis).
   FIXME: malloc in user code and free in mdk may crash if mixed debug and release(vcrt)
   Callback is called in a dedicated thread, so time-consuming operations(encode, file io etc.) are allowed in the callback.
 */
    using SnapshotCallback = std::function<std::string(const SnapshotRequest* req, double frameTime)>;
/*!
  \brief snapshot
  take a snapshot from current renderer. The result is in bgra format, or null on failure.
  When `snapshot()` is called, redraw is scheduled for `vo_opaque`'s renderer, then renderer will take a snapshot in rendering thread.
  So for a foreign context, if renderer's surface/window/widget is invisible or minimized, snapshot may do nothing because of system or gui toolkit painting optimization.
*/
    void snapshot(const SnapshotRequest* request, const SnapshotCallback& cb, void* vo_opaque = nullptr) {
        SnapshotCallback* f = cb ? new SnapshotCallback(cb) : nullptr;
        mdkSnapshotCallback callback;
        callback.cb = [](mdkSnapshotRequest* req, double frameTime, void* opaque){
            auto f = (SnapshotCallback*)opaque;
            std::string file;
            if (f)
                file = (*f)((SnapshotRequest*)req, frameTime);
            delete f;
            if (file.empty())
                return (char*)nullptr;
            return MDK_strdup(file.data());
        };
        callback.opaque = f;
        return MDK_CALL(p, snapshot, (mdkSnapshotRequest*)request, callback, vo_opaque);
    }


/*!
  see https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-setpropertyconst-stdstring-key-const-stdstring-value
  Predefined properties are:
  - "continue_at_end" or "keep_open": do not stop playback when decode and render to end of stream. Useful for [timeline preview](https://github.com/wang-bin/mdk-sdk/wiki/Typical-Usage#timeline-preview). only setState(State::Stopped) can stop playback
  - "audio.decoders": decoder list for setDecoders(), with or without decoder properties. "name1,name2:key21=val21"
  - "video.decoders": decoder list for setDecoders(), with or without decoder properties. "name1,name2:key21=val21"
  - "audio.decoder": audio decoder properties, value is "key=value" or "key1=value1:key2=value2". override "decoder" properties. key-values can be FFmpeg options(AVOption) for ffmpeg based decoders
  - "video.decoder": video decoder properties, value is "key=value" or "key1=value1:key2=value2". override "decoder" properties. key-values can be FFmpeg options(AVOption) for ffmpeg based decoders
  - "decoder": video and audio decoder properties, value is "key=value" or "key1=value1:key2=value2". key-values can be FFmpeg options(AVOption) for ffmpeg based decoders
  - "record.copyts", "recorder.copyts": "1" or "0"(default), use input packet timestamp, or correct packet timestamp to be continuous.
  - "record.$opt_name": option for recorder's muxer or io, `opt_name` can also be an ffmpeg option, e.g. "record.avformat.$opt_name" and "record.avio.$opt_name".
  - "reader.decoder.$DecoderName": $DecoderName decoder properties, value is "key=value" or "key1=value1:key2=value2". override "decoder" properties. key-values can be FFmpeg options(AVOption) for ffmpeg based decoders
  - "reader.starts_with_key": "0" or "1"(default). if "1", recorder and video decoder starts with key-frame, and drop non-key packets before the first decode.
  - "buffer" or "buffer.range": parameters setBufferRange(). value is "minMs", "minMs+maxMs", "minMs+maxMs-", "minMs-". the last '-' indicates drop mode
  - "demux.buffer.ranges": default "0". set a positive integer to enable demuxer's packet cache(if protocol is listed in property "demux.buffer.protocols"), the value is cache ranges count. Cache is useful for network streams, download data only once(if a cache range is not dropped), speedup seeking. Cache ranges are increased by seeking to a uncached position, decreased by merging ranges which are overlapped and LRU algorithm.
  - "demux.buffer.protocols": default is "http,https". only these protocols will enable demuxer cache.
  - "demux.max_errors": continue to demux the stream if error count is less than this value. same as global option "demuxer.max_errors"

#### FFmpeg properties
  - "avformat.$opt_name": avformat option via AVOption, e.g. {"avformat.fpsprobesize": "0"}. if global option "demuxer.io=0", it also can be AVIOContext/URLProtocol option. `video_codec_id, audio_codec_id and subtitle_codec_id` are also supported even are not AVOption, value is codec name. `video_codec_id` is useful for capture devices with multiple codecs supported.
  - "avio.$opt_name": AVIOContext/URLProtocol option, e.g. `avio.user_agent` for UA, `avio.headers` for http headers.
  - "avcodec.$opt_name": AVCodecContext option, will apply for all FFmpeg based video/audio/subtitle decoders. To set for a single decoder, use [setDecoders() with properties](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-setdecodersmediatype-type-const-stdvectorstdstring-names).
  - "video.avfilter": ffmpeg avfilter filter graph string for video track. take effect immediately when playing(not paused). **ONLY WORKS WITH SOFTWARE DECODERS**
  - "audio.avfilter": ffmpeg avfilter filter graph string for audio track. take effect immediately when playing(not paused).

#### Subtitle properties
  - "cc": "0" or "1"(default). enable closed caption decoding and rendering.
  - "subtitle": "0" or "1"(default). enable subtitle(including cc) rendering. `setActiveTracks(MediaType::Subtitle, {...})` enables decoding only. if rendering is disabled, you can still use subtitleText() to draw your self
  - "subtitle.size": non-bitmap subtitle resolution, can be "video" to use video frame size(default), otherwise use video renderer size(multiple renderers is undefined)

style properties for all subtitle types(text, ass/ssa and bitmaps):
  - "subtitle.scale": scale subtitle, default is 1, .i.e no scale.
style properties(for srt, subrip, text etc, not ass/ssa):
  - "subtitle.font": font name, can be empty(default)
  - "subtitle.font.size": font size, default is 22
  - "subtitle.font.spacing": font spacing between chars, float value string. default is "0"
  - "subtitle.bold", "subtitle.font.bold": bold, "0"(default) or "1"
  - "subtitle.italic", "subtitle.font.italic": italic, "0"(default) or "1"
  - "subtitle.underline", "subtitle.font.underline": underline, "0"(default) or "1"
  - "subtitle.strikeout", "subtitle.font.strikeout": strikeout, "0"(default) or "1"
  - "subtitle.color": font color. rgba integer value of base 10 or 16, default is "0xffffffff"
  - "subtitle.color.outline": outline color. rgba integer value of base 10 or 16, default is "0x000000ff"
  - "subtitle.color.background": shadow or background box color. rgba integer value of base 10 or 16, default is "0"
  - "subtitle.border": border size, float value, default is "1.2"
  - "subtitle.shadow": shadow size, float value, default is "0". if < 0, will show background box if "box" value >=0
  - "subtitle.box": background box edge width, float value, default is "0". if < 0, will show shadow if "shadow" value > 0
  - "subtitle.alignment.x": horizontal aligment, value can be "-1": left, "0": center, "1": right
  - "subtitle.alignment.y": vertical aligment, value can be "-1": top, "0": center, "1": bottom
  - "subtitle.margin.x": horizontal margin, int value, default "10". no effect if align to horizontal center
  - "subtitle.margin.y": vertical margin, int value, default "10". no effect if align to vertical center
  - "subtitle.blur": blur size, default 0. blur border/outline and shadow.
 */
    void setProperty(const std::string& key, const std::string& value) {
        MDK_CALL(p, setProperty, key.data(), value.data());
    }

    template<typename T, typename std::enable_if<std::is_arithmetic<T>::value, bool>::type = true>
    void setProperty(const std::string& key, T value) {
        return setProperty(key, std::to_string(value));
    }

    std::string property(const std::string& key, const std::string& defaultValue = std::string()) const {
        auto value = MDK_CALL(p, getProperty, key.data());
        if (!value)
            return defaultValue;
        return value;
    }
// A vo/renderer (e.g. the default vo/renderer) is gfx context aware, i.e. can render in multiple gfx contexts with a single vo/renderer, but parameters(e.g. surface size)
// must be updated when switch to a new context. So per gfx context vo/renderer can be better because parameters are stored in vo/renderer.
/*!
  \brief getVideoFrame
  get current rendered frame, i.e. the decoded video frame rendered by renderVideo()
 */
    void getVideoFrame(VideoFrame* frame, void* vo_opaque = nullptr);
/*
  \brief setVideoSurfaceSize
  Window size, surface size or drawable size. Render callback(if exists) will be invoked if width and height > 0.
  Usually for foreign contexts, i.e. not use updateNativeSurface().
NOTE:
  If width or heigh < 0, corresponding video renderer (for vo_opaque) will be removed and gfx resources will be released(need the context to be current for GL).
  But subsequence call with this vo_opaque will create renderer again. So it can be used before destroying the renderer.
  OpenGL: resources must be released by setVideoSurfaceSize(-1, -1, ...) in a correct context. If player is destroyed before context, MUST call Player::foreignGLContextDestroyed() when destroying the context.
 */
    void setVideoSurfaceSize(int width, int height, void* vo_opaque = nullptr) {
        MDK_CALL(p, setVideoSurfaceSize, width, height, vo_opaque);
    }
/*!
  \brief setVideoViewport
  The rectangular viewport where the scene will be drawn relative to surface viewport.
  x, y, w, h are normalized to [0, 1]
*/
    void setVideoViewport(float x, float y, float w, float h, void* vo_opaque = nullptr) {
        MDK_CALL(p, setVideoViewport, x, y, w, h, vo_opaque);
    }
/*!
  \brief setAspectRatio
  Video display aspect ratio.
  IgnoreAspectRatio(0): ignore aspect ratio and scale to fit renderer viewport
  KeepAspectRatio(default): keep frame aspect ratio and scale as large as possible inside renderer viewport
  KeepAspectRatioCrop: keep frame aspect ratio and scale as small as possible outside renderer viewport
  other value > 0: like KeepAspectRatio, but keep given aspect ratio and scale as large as possible inside renderer viewport
  other value < 0: like KeepAspectRatioCrop, but keep given aspect ratio and scale as small as possible inside renderer viewport
 */
    void setAspectRatio(float value, void* vo_opaque = nullptr) {
        MDK_CALL(p, setAspectRatio, value, vo_opaque);
    }
/*!
  \brief rotate
  rotate around video frame center
  \param degree: 0, 90, 180, 270, counterclockwise
 */
    void rotate(int degree, void* vo_opaque = nullptr) {
        MDK_CALL(p, rotate, degree, vo_opaque);
    }
/*!
  \brief scale
  scale frame size. x, y can be < 0, means scale and flip.
*/
    void scale(float x, float y, void* vo_opaque = nullptr) {
        MDK_CALL(p, scale, x, y, vo_opaque);
    }

    enum MapDirection {
        FrameToViewport, // left-hand
        ViewportToFrame, // left-hand
    };
/*!
  \brief mapPoint
  map a point from one coordinates to another. a frame must be rendered. coordinates is normalized to [0, 1].
  \param x points to x coordinate of viewport or currently rendered video frame
  \param z not used
*/
    void mapPoint(MapDirection dir, float* x, float* y, float* z = nullptr, void* vo_opaque = nullptr) {
        MDK_CALL(p, mapPoint, MDK_MapDirection(dir), x, y, z, vo_opaque);
    }

/*!
  \brief setPointMap
  Can be called on any thread
  \param videoRoi: array of 2d point (x, y) in video frame. coordinate: top-left = (0, 0), bottom-right=(1, 1). set null to disable mapping
  \param viewRoi: array of 2d point (x, y) in video renderer. coordinate: top-left = (0, 0), bottom-right=(1, 1). null is the whole renderer.
  \param count: point count. only support 2. set 0 to disable mapping
 */
    void setPointMap(const float* videoRoi, const float* viewRoi = nullptr, int count = 2, void* vo_opaque = nullptr) {
        MDK_CALL(p, setPointMap, videoRoi, viewRoi, count, vo_opaque);
    }
/*
  RenderAPI
  RenderAPI provides platform/api dependent resources for video renderer and rendering context corresponding to vo_opaque. It's used by
  1. create internal render context via updateNativeSurface() using given api. MUST be called before any other functions have parameter vo_opaque and updateNativeSurface()!
    To use RenderAPI other than OpenGL, setRenderAPI() MUST be called before add/updateNativeSurface(), and vo_opaque MUST be the surface or nullptr.
    If vo_opaque is nullptr, i.e. the default, then all context will have the same RenderAPI type, and call setRenderAPI() once is enough.
    If vo_opaque is surface(not null), each surface can have it's own RenderAPI type.
    RenderAPI members will be initialized when a rendering context for surface is created, and keep valid in rendering functions like renderVideo()
  2. Set foreign context provided by user. setRenderAPI() and other functions with vo_opaque parameter can be called in any order
  3. render. renderVideo() will use the given api for vo_opaque

  If setRenderAPI() is not called by user, a default one (usually GLRenderAPI) is used, thus renderAPI() always not null.
  setRenderAPI() is not thread safe, so usually called before rendering starts, or native surface is set.
*/

/*!
  \brief setRenderAPI
  set render api for a vo, useful for non-opengl(no way to get current context)
  \param api
  To release gfx resources, set null api in rendering thread/context(required by vulkan)
 */
    Player& setRenderAPI(const RenderAPI* api, void* vo_opaque = nullptr) {
        MDK_CALL(p, setRenderAPI, reinterpret_cast<const mdkRenderAPI*>(api), vo_opaque);
        return *this;
    }
/*!
  \brief renderApi()
  get render api. For offscreen rendering, may only api type be valid in setRenderAPI(), and other members are filled internally, and used by user after renderVideo()
 */
    RenderAPI* renderAPI(void* vo_opaque = nullptr) const {
        return reinterpret_cast<RenderAPI*>(MDK_CALL(p, renderAPI, vo_opaque));
    }

/*!
   \brief renderVideo
  Render the next or current(redraw) frame. Foreign render context only (i.e. not created by createSurface()/updateNativeSurface()).
  OpenGL: Can be called in multiple foreign contexts for the same vo_opaque.
   \return timestamp of rendered frame, or < 0 if no frame is rendered. precision is microsecond
 */
    double renderVideo(void* vo_opaque = nullptr) {
        return MDK_CALL(p, renderVideo, vo_opaque);
    }
/*!
  \brief enqueue
  Send the frame to video renderer. You must call renderVideo() later in render thread
*/
    void enqueue(const VideoFrame& frame, void* vo_opaque = nullptr) {
        MDK_CALL2(p, enqueueVideo, frame.toC(), vo_opaque);
    }
/*!
  \brief setBackgroundColor
  r, g, b, a range is [0, 1]. default is 0. if out of range, background color will not be filled
 */
    void setBackgroundColor(float r, float g, float b, float a, void* vo_opaque = nullptr) {
        return MDK_CALL(p, setBackgroundColor, r, g, b, a, vo_opaque);
    }

    Player& set(VideoEffect effect, const float& values, void* vo_opaque = nullptr) {
        MDK_CALL(p, setVideoEffect, MDK_VideoEffect(effect), &values, vo_opaque);
        return *this;
    }
/*!
  \brief set
  Set output color space.
  \param value
    - invalid (ColorSpaceUnknown): renderer will try to use the value of decoded frame, and will send hdr10 metadata when possible. i.e. hdr videos will enable hdr display. Currently only supported by metal, and `MetalRenderAPI.layer` must be a `CAMetalLayer` ([example](https://github.com/wang-bin/swift-mdk/blob/master/Player.swift#L184))
    - hdr colorspace (ColorSpaceBT2100_PQ): no hdr metadata will be sent to the display, sdr will map to hdr. Can be used by the gui toolkits which support hdr swapchain but no api to change swapchain colorspace and format on the fly, see [Qt example](https://github.com/wang-bin/mdk-examples/blob/master/Qt/qmlrhi/VideoTextureNodePub.cpp#L83)
    - sdr color space (ColorSpaceBT709): the default. HDR videos will tone map to SDR.
*/
    Player& set(ColorSpace value, void* vo_opaque = nullptr) {
        MDK_CALL(p, setColorSpace, MDK_ColorSpace(value), vo_opaque);
        return *this;
    }

/*!
  \brief setRenderCallback
  set a callback which is invoked when the vo coresponding to vo_opaque needs to update/draw content, e.g. when a new frame is received in the renderer.
  Also invoked in setVideoSurfaceSize(), setVideoViewport(), setAspectRatio() and rotate(), take care of dead lock in callback and above functions.
  with vo_opaque, user can know which vo/renderer is rendering, useful for multiple renderers
  There may be no frames or playback not even started, but renderer update is required internally

  DO NOT call renderVideo() in the callback, otherwise will results in dead lock
*/
    void setRenderCallback(const std::function<void(void* vo_opaque)>& cb) { // per vo?
        {
            const std::lock_guard<std::mutex> lock(render_mtx_);
            render_cb_ = cb;
        }
        mdkRenderCallback callback;
        callback.cb = [](void* vo_opaque, void* opaque){
            auto p = (Player*)opaque;
            const std::lock_guard<std::mutex> lock(p->render_mtx_);
            if (p->render_cb_)
                p->render_cb_(vo_opaque);
        };
        callback.opaque = render_cb_ ? this : nullptr;
        MDK_CALL(p, setRenderCallback, callback);
    }

/*!
  \brief onFrame
  A callback to be invoked before delivering a frame to renderers. Frame can be VideoFrame and AudioFrame(NOT IMPLEMENTED).
  The callback can be used as a filter.
  TODO: frames not in host memory
  \param cb callback to be invoked. returns pending number of frames. callback parameter is input and output frame. if input frame is an invalid frame, output a pending frame.
  For most filters, 1 input frame generates 1 output frame, then return 0.
 */
    template<class Frame>
    Player& onFrame(const std::function<int(Frame&, int/*track*/)>& cb);
/*!
  \brief position
  Current playback time in milliseconds. Relative to media's first timestamp, which usually is 0.
  If has active video tracks, it's currently presented video frame time. otherwise, it's audio time.
 */
    int64_t position() const {
        return MDK_CALL(p, position);
    }
/*!
  \brief seek
  \param pos seek target. if flags has SeekFlag::Frame, pos is frame count, otherwise it's milliseconds.
  If pos > media time range, e.g. INT64_MAX, will seek to the last frame of media for SeekFlag::AnyFrame, and the last key frame of media for SeekFlag::Fast.
  If pos > media time range with SeekFlag::AnyFrame, playback will stop unless setProperty("continue_at_end", "1") was called
  FIXME: a/v sync broken if SeekFlag::Frame|SeekFlag::FromNow.
  \param cb if succeeded, callback is called when stream seek finished and after the 1st frame decoded or decode error(e.g. video tracks disabled), ret(>=0) is the timestamp of the 1st frame(video if exists) after seek.
  If error(io, demux, not decode) occured(ret < 0, usually -1) or skipped because of unfinished previous seek(ret == -2), out of range(-4) or media unloaded(-3).
 */
    bool seek(int64_t pos, SeekFlag flags, const std::function<void(int64_t)>& cb = nullptr) {
        std::function<void(int64_t)>* f = cb ? new std::function<void(int64_t)>(cb) : nullptr;
        mdkSeekCallback callback;
        callback.cb = [](int64_t ms, void* opaque){
            auto f = (std::function<void(int64_t)>*)opaque;
            if (f)
                (*f)(ms);
            delete f;
        };
        callback.opaque = f;
        return MDK_CALL(p, seekWithFlags, pos, MDK_SeekFlag(flags), callback);
    }

    bool seek(int64_t pos, const std::function<void(int64_t)>& cb = nullptr) {
        return seek(pos, SeekFlag::Default, cb);
    }

    void setPlaybackRate(float value) {
        MDK_CALL(p, setPlaybackRate, value);
    }

    float playbackRate() const {
        return MDK_CALL(p, playbackRate);
    }
/*!
  \brief bufferedTimeRanges
  time(position) is relative to media start time.
  Available if demuxer cache is enabled by property "demux.buffer.ranges" and "demux.buffer.protocols"
*/
    std::vector<TimeRange> bufferedTimeRanges() const {
        std::vector<TimeRange> rs(16);
        const auto count = (size_t)MDK_CALL(p, bufferedTimeRanges, (int64_t*)&rs[0], (int)rs.size());
        if (count > rs.size()) {
            rs.resize(count);
            MDK_CALL(p, bufferedTimeRanges, (int64_t*)&rs[0], (int)rs.size());
        } else {
            rs.resize(count);
        }
        return rs;
    }
/*!
 * \brief buffered
 * get buffered undecoded data duration and size
 * \return buffered data(packets) duration
 */
    int64_t buffered(int64_t* bytes = nullptr) const {
        return MDK_CALL(p, buffered, bytes);
    }
/*!
  \brief bufferRange
  set duration range of buffered data.
  \param minMs default 1000. wait for buffered duration >= minMs when before popping a packet.
    If minMs < 0, then minMs, maxMs and drop will be reset to the default value.
    If minMs > 0, when packets queue becomes empty, `MediaStatus::Buffering` will be set until queue duration >= minMs, "reader.buffering" MediaEvent
    will be triggered.
    If minMs == 0, decode ASAP.
  \param maxMs default 4000. max buffered duration. Large value is recommended. Latency is not affected.
    If maxMs < 0, then maxMs and drop will be reset to the default value
    If maxMs == 0, same as INT64_MAX
  drop = true:
    drop old non-key frame packets to reduce buffered duration until < maxMs. If maxMs(!=0 or INT64_MAX) is smaller than key-frame interval, no drop effect.
    If maxMs == 0 or INT64_MAX, always drop old packets and keep at most 1 key-frame packet
  drop = false: wait for buffered duration < maxMs before pushing packets

  For realtime streams like(rtp, rtsp, rtmp sdp etc.), the default range is [0, INT64_MAX, true].
  Usually you don't need to call this api. This api can be used for low latency live videos, for example setBufferRange(0, INT64_MAX, true) will decode as soon as possible when media data received, and no accumulated delay.
 */
    void setBufferRange(int64_t minMs = -1, int64_t maxMs = -1, bool drop = false) {
        MDK_CALL(p, setBufferRange, minMs, maxMs, drop);
    }
/*!
  \brief switchBitrate
  A new media will be played later
  \param delay switch after at least delay ms. TODO: determined by buffered time, e.g. from high bit rate without enough buffered samples to low bit rate
  \param cb (true/false) called when finished/failed
  \param flags seek flags for the next url, accurate or fast
 */
    void switchBitrate(const char* url, int64_t delay = -1, const std::function<void(bool)>& cb = nullptr) {
        {
            const std::lock_guard<std::mutex> lock(switch_mtx_);
            switch_cb_ = cb;
        }
        SwitchBitrateCallback callback;
        callback.cb = [](bool value, void* opaque){
            auto p = (Player*)opaque;
            const std::lock_guard<std::mutex> lock(p->switch_mtx_);
            if (p->switch_cb_)
                p->switch_cb_(value);
        };
        callback.opaque = switch_cb_ ? this : nullptr;
        return MDK_CALL(p, switchBitrate, url, delay, callback);
    }
/*!
 * \brief switchBitrateSingalConnection
 * Only 1 media is loaded. The previous media is unloaded and the playback continues. When new media is preloaded, stop the previous media at some point
 * MUST call setPreloadImmediately(false) because PreloadImmediately for singal connection preload is not possible.
 * \return false if preload immediately
 * This will not affect next media set by user
 */
    bool switchBitrateSingleConnection(const char *url, const std::function<void(bool)>& cb = nullptr) {
        switch_cb_ = cb;
        SwitchBitrateCallback callback;
        callback.cb = [](bool value, void* opaque){
            auto f = (std::function<void(bool)>*)opaque;
            (*f)(value);
        };
        callback.opaque = switch_cb_ ? (void*)&switch_cb_ : nullptr;
        return MDK_CALL(p, switchBitrateSingleConnection, url, callback);
    }

/*!
  \brief onEvent
  Add/Remove a [MediaEvent](https://github.com/wang-bin/mdk-sdk/wiki/Types#class-mediaevent) listener, or remove listeners.
  callback return: true if event is processed and should stop dispatching.
 */
    Player& onEvent(const std::function<bool(const MediaEvent&)>& cb, CallbackToken* token = nullptr) {
        mdkMediaEventCallback callback{};
        const std::lock_guard<std::mutex> lock(event_mtx_);
        if (!cb) {
            MDK_CALL(p, onEvent, callback, token ? &event_cb_key_[*token] : nullptr);
            if (token) {
                event_cb_.erase(*token);
                event_cb_key_.erase(*token);
            } else {
                event_cb_.clear();
                event_cb_key_.clear();
            }
        } else {
            static CallbackToken k = 1;
            event_cb_[k] = cb;
            callback.cb = [](const mdkMediaEvent* me, void* opaque){
                auto f = (std::function<bool(const MediaEvent&)>*)opaque;
                MediaEvent e;
                e.error = me->error;
                e.category = me->category;
                e.detail = me->detail;
                e.decoder.stream = me->decoder.stream;
                e.video.width = me->video.width;
                e.video.height = me->video.height;
                return (*f)(e);
            };
            callback.opaque = &event_cb_[k];
            CallbackToken t;
            MDK_CALL(p, onEvent, callback, &t);
            event_cb_key_[k] = t;
            if (token)
                *token = t;
            k++;
        }
        return *this;
    }
/*
  \brief record
  Start to record or stop recording current media by remuxing packets read. If media is not loaded, recorder will start when playback starts
  \param url destination. null or the same value as recording one to stop recording. can be a local file, or a network stream
  \param format forced format. if null, guess from url. if null and format guessed from url does not support all codecs of current media, another suitable format will be used
  examples:
    player.record("record.mov");
    player.record("rtmp://127.0.0.1/live/0", "flv");
    player.record("rtsp://127.0.0.1/live/0", "rtsp");
 */
    void record(const char* url = nullptr, const char* format = nullptr) {
        MDK_CALL(p, record, url, format);
    }

/*!
  \brief setLoop
  Set A-B loop repeat count.
  \param count repeat count. 0 to disable looping and stop when out of range(B)
 */
    void setLoop(int count) {
        MDK_CALL(p, setLoop, count);
    }
/*
  \brief onLoop
  add/remove a callback which will be invoked right before a new A-B loop
  \param cb callback with current loop count elapsed
 */
    Player& onLoop(const std::function<void(int)>& cb, CallbackToken* token = nullptr) {
        mdkLoopCallback callback{};
        const std::lock_guard<std::mutex> lock(loop_mtx_);
        if (!cb) {
            MDK_CALL(p, onLoop, callback, token ? &loop_cb_key_[*token] : nullptr);
            if (token) {
                loop_cb_.erase(*token);
                loop_cb_key_.erase(*token);
            } else {
                loop_cb_.clear();
                loop_cb_key_.clear();
            }
        } else {
            static CallbackToken k = 1;
            loop_cb_[k] = cb;
            callback.cb = [](int countNow, void* opaque){
                auto f = (std::function<void(int)>*)opaque;
                return (*f)(countNow);
            };
            callback.opaque = &loop_cb_[k];
            CallbackToken t;
            MDK_CALL(p, onLoop, callback, &t);
            loop_cb_key_[k] = t;
            if (token)
                *token = t;
            k++;
        }
        return *this;
    }
/*!
  \brief setRange
  Set A-B loop range, or playback range
  \param a loop position begin, in ms.
  \param b loop position end, in ms. -1, INT64_MAX or numeric_limit<int64_t>::max() indicates b is the end of media
 */
    void setRange(int64_t a, int64_t b = INT64_MAX) {
        MDK_CALL(p, setRange, a, b);
    }

/*!
  \brief onSync
  \param cb a callback invoked when about to render a frame. return expected current playback position(seconds), e.g. DBL_MAX(TimestampEOS) indicates render video frame ASAP.
  sync callback clock should handle pause, resume, seek and seek finish events
 */
    Player& onSync(const std::function<double()>& cb, int minInterval = 10) {
        {
            const std::lock_guard<std::mutex> lock(sync_mtx_);
            sync_cb_ = cb;
        }
        mdkSyncCallback callback;
        callback.cb = [](void* opaque){
            auto p = (Player*)opaque;
            const std::lock_guard<std::mutex> lock(p->sync_mtx_);
            if (!p->sync_cb_)
                return 0.0;
            return p->sync_cb_();
        };
        callback.opaque = sync_cb_ ? this : nullptr;
        MDK_CALL(p, onSync, callback, minInterval);
        return *this;
    }

/*!
  \brief subtitleText
  get subtitle text. only for text based subtitle, e.g. ass, srt
  \param time in second. if < 0, get currently rendered text
  \param style ass style option. 0: no style, plain text. 1: ass style. 2: full ass style
*/
    std::string subtitleText(double time = -1, int style = 0) const {
        std::string s;
        mdkSubtitleCallback cb;
        cb.cb = [](const char* text, void* opaque) {
            auto s = (std::string*)opaque;
            if (text)
                *s = text;
        };
        cb.opaque = &s;
        MDK_CALL(p, subtitleText, time, style, cb);
        return s;
    }

#if !MDK_VERSION_CHECK(1, 0, 0)
#if (__cpp_attributes+0)
[[deprecated("use setDecoders(MediaType::Audio, names) instead")]]
#endif
    void setAudioDecoders(const std::vector<std::string>& names) {
        setDecoders(MediaType::Audio, names);
    }
#if (__cpp_attributes+0)
[[deprecated("use setDecoders(MediaType::Video, names) instead")]]
#endif
    void setVideoDecoders(const std::vector<std::string>& names) {
        setDecoders(MediaType::Video, names);
    }
#if (__cpp_attributes+0)
[[deprecated("use set(State) instead")]]
#endif
    void setState(PlaybackState value) {
        set(value);
    }
#endif
private:
    const mdkPlayerAPI* p = nullptr;
    bool owner_ = true;
    bool mute_ = false;
    float volume_ = 1.0f;
    std::function<void()> current_cb_ = nullptr;
    std::mutex current_mtx_;
    std::function<bool(int64_t ms)> timeout_cb_ = nullptr;
    std::mutex timeout_mtx_;
    std::function<void(State)> state_cb_ = nullptr;
    std::mutex state_mtx_;
    std::function<void(void* vo_opaque)> render_cb_ = nullptr;
    std::mutex render_mtx_;
    std::function<void(bool)> switch_cb_ = nullptr;
    std::mutex switch_mtx_;
    std::function<int(AudioFrame&, int/*track*/)> audio_cb_ = nullptr;
    std::mutex audio_mtx_;
    std::function<int(VideoFrame&, int/*track*/)> video_cb_ = nullptr;
    std::mutex video_mtx_;
    std::function<double()> sync_cb_ = nullptr;
    std::mutex sync_mtx_;
    std::map<CallbackToken, std::function<bool(const MediaEvent&)>> event_cb_; // rb tree, elements never destroyed
    std::map<CallbackToken,CallbackToken> event_cb_key_;
    std::mutex event_mtx_;
    std::map<CallbackToken, std::function<void(int)>> loop_cb_; // rb tree, elements never destroyed
    std::map<CallbackToken,CallbackToken> loop_cb_key_;
    std::mutex loop_mtx_;
    std::map<CallbackToken, std::function<bool(MediaStatus, MediaStatus)>> status_cb_;
    std::map<CallbackToken,CallbackToken> status_cb_key_;
    std::mutex status_mtx_;

    mutable MediaInfo info_;
};


template<>
inline Player& Player::onFrame(const std::function<int(VideoFrame&, int/*track*/)>& cb)
{
    {
        const std::lock_guard<std::mutex> lock(video_mtx_);
        video_cb_ = cb;
    }
    mdkVideoCallback callback;
    callback.cb = [](mdkVideoFrameAPI** pFrame/*in/out*/, int track, void* opaque){
        VideoFrame frame;
        frame.attach(*pFrame);
        auto p = (Player*)opaque;
        const std::lock_guard<std::mutex> lock(p->video_mtx_);
        if (!p->video_cb_)
            return 0;
        const auto pendings = p->video_cb_(frame, track);
        *pFrame = frame.detach();
        return pendings;
    };
    callback.opaque = video_cb_ ? this : nullptr;
    MDK_CALL(p, onVideo, callback);
    return *this;
}

template<>
inline Player& Player::onFrame(const std::function<int(AudioFrame&, int/*track*/)>& cb)
{
    {
        const std::lock_guard<std::mutex> lock(audio_mtx_);
        audio_cb_ = cb;
    }
    mdkAudioCallback callback;
    callback.cb = [](mdkAudioFrameAPI** pFrame/*in/out*/, int track, void* opaque){
        AudioFrame frame;
        frame.attach(*pFrame);
        auto p = (Player*)opaque;
        const std::lock_guard<std::mutex> lock(p->audio_mtx_);
        if (!p->audio_cb_)
            return 0;
        const auto pendings = p->audio_cb_(frame, track);
        *pFrame = frame.detach();
        return pendings;
    };
    callback.opaque = audio_cb_ ? this : nullptr;
    MDK_CALL(p, onAudio, callback);
    return *this;
}

MDK_NS_END
