#ifndef ERIKA_H
#define ERIKA_H

/*
 * liberika media playback engine — C ABI.
 *
 * Full reference: docs/capi_reference.md. Embedding walkthrough:
 * docs/integration.md.
 *
 * Two independent entry points; pick one per integration:
 *   - ErikaHandle:          pull model. The host renders and pulls state.
 *   - ErikaPresenterHandle: push model. liberika owns decode/timing/audio/render;
 *                           the host gives it a surface and calls render_tick.
 *                           Compiled on macOS / iOS / Windows / Android /
 *                           OpenHarmony / Linux; on other targets
 *                           erika_presenter_create returns NULL.
 *
 * Conventions:
 *   - Every fallible call returns ErikaStatus; Ok (0) and NoEvent are the only
 *     non-error results. Panics are caught and surface as ErikaStatus_Panic.
 *   - On a non-Ok/NoEvent result a human-readable message is stored in a
 *     THREAD-LOCAL slot; read it on the same thread via
 *     erika_last_error_message() and free with erika_string_free().
 *   - Any char* liberika returns is caller-owned: free standalone strings with
 *     erika_string_free(); free strings inside ErikaTrackInfo /
 *     ErikaDanmakuTrackInfo with the matching *_info_free() function.
 *   - const char* arguments are borrowed for the call only and must be
 *     NUL-terminated UTF-8.
 *   - List getters use the counted-array idiom: pass (buf, capacity, &len);
 *     len is set to the total count, at most capacity records are written, and
 *     capacity 0 with a NULL buffer queries the count.
 *   - attach and resize functions take exact width/height in physical pixels.
 *     The scale is the independent logical-content/DPI scale used for UI such
 *     as danmaku; it never multiplies the surface extent.
 *   - A handle is not internally synchronized: do not call into one handle
 *     concurrently from multiple threads.
 */

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handles. ErikaHandle = pull model, ErikaPresenterHandle = push model. */
typedef struct ErikaHandle ErikaHandle;
typedef struct ErikaPresenterHandle ErikaPresenterHandle;
/* A media kept open for taking many pictures; see erika_frame_export_session_open. */
typedef struct ErikaFrameExportSession ErikaFrameExportSession;

typedef struct ErikaHttpHeader {
  const char *name;
  const char *value;
} ErikaHttpHeader;

/* Extended open parameters for erika_open_with_options /
 * erika_presenter_open_with_options. Pass zero for fields you do not use;
 * reserved must be zero. http_read_ahead_bytes overrides the HTTP(S)
 * read-ahead window (in bytes); 0 uses ERIKA_HTTP_READAHEAD_BYTES when set,
 * otherwise the 2 MiB default. http_back_buffer_bytes overrides the HTTP(S)
 * rewind budget (in bytes): how much already-played data stays cached so a
 * rewind inside it is served without a network request; 0 uses the 16 MiB
 * default (a -10 s skip at 71 Mbps covers ~89 MB, so hosts playing
 * high-bitrate media should size this from the bitrate).
 * start_position_micros opens the media there instead of at its start: the
 * engine seeks before presenting, so the first frame shown is the one at that
 * position; 0 opens at the start (it was the first reserved slot, so callers
 * that zero the struct keep opening at the start). */
typedef struct ErikaOpenOptions {
  const ErikaHttpHeader *headers;
  uintptr_t header_count;
  uint64_t http_read_ahead_bytes;
  uint64_t http_back_buffer_bytes;
  uint64_t start_position_micros;
  uint64_t reserved[1];
} ErikaOpenOptions;

/* Headless GIF export. Times are milliseconds. The function is synchronous;
 * UI integrations must call it from a worker thread. It owns an independent
 * demux/decode/encode pipeline and requires no player or presenter handle. */
typedef enum ErikaGifExportQuality {
  ErikaGifExportQuality_Normal = 0,
  ErikaGifExportQuality_High = 1,
} ErikaGifExportQuality;

typedef struct ErikaGifExportOptions {
  const char *input_uri;
  const char *output_path;
  uint64_t start_millis;
  uint64_t end_millis;
  uint32_t frames_per_second;
  uint32_t output_width;
  uint32_t output_height;
  int32_t quality;
  int32_t loop_count;
  bool overwrite;
  const ErikaHttpHeader *headers;
  uintptr_t header_count;
  uint64_t http_read_ahead_bytes;
  uint64_t reserved[3];
} ErikaGifExportOptions;

typedef struct ErikaGifExportResult {
  uint32_t width;
  uint32_t height;
  uint64_t frame_count;
  uint64_t file_size;
} ErikaGifExportResult;

/* Headless single-frame export: the picture shown at position_millis (a
 * media time) as RGBA or PNG. max_width/max_height bound the output (0 =
 * unbounded); the display aspect ratio is kept and the picture is never
 * larger than the video. HDR sources (PQ, HLG, Dolby Vision) are tone mapped
 * to SDR the way Erika renders them on an SDR display. Synchronous; UI
 * integrations must call it from a worker thread. Owns an independent
 * demux/decode pipeline (multi-threaded software decoding) and requires no
 * player or presenter handle. */
typedef enum ErikaFrameExportFormat {
  ErikaFrameExportFormat_Rgba = 0, /* rows of width * 4 bytes, alpha 255 */
  ErikaFrameExportFormat_Png = 1,  /* PNG file bytes, 8-bit RGB */
} ErikaFrameExportFormat;

typedef struct ErikaFrameExportOptions {
  const char *input_uri;
  const ErikaHttpHeader *headers;
  uintptr_t header_count;
  uint64_t position_millis;
  uint64_t http_read_ahead_bytes;
  uint32_t max_width;
  uint32_t max_height;
  int32_t format;
  uint32_t reserved_flags;
  uint64_t reserved[4];
} ErikaFrameExportOptions;

/* data stays owned by liberika until erika_frame_export_result_free. Times
 * are microseconds: timestamp_micros is where the picture is, duration_micros
 * the media duration (0 when the container reports none). reserved_flags
 * carries ERIKA_FRAME_EXPORT_TONE_MAPPED when the picture was tone mapped. */
#define ERIKA_FRAME_EXPORT_TONE_MAPPED 1u

typedef struct ErikaFrameExportResult {
  uint8_t *data;
  uintptr_t data_len;
  uint64_t timestamp_micros;
  uint64_t duration_micros;
  uint32_t width;
  uint32_t height;
  uint32_t source_width;
  uint32_t source_height;
  int32_t format;
  uint32_t reserved_flags;
  uint64_t reserved[2];
} ErikaFrameExportResult;

/* Frame export session: the media is opened once and pictures are taken from
 * it one after another. A request after the previous one continues decoding
 * from where the decoder stopped when no keyframe lies between, and seeks
 * otherwise (backwards included), so requests in ascending time order are the
 * cheapest. Results are the same as erika_export_frame's. */
typedef struct ErikaFrameExportSessionOptions {
  const char *input_uri;
  const ErikaHttpHeader *headers;
  uintptr_t header_count;
  uint64_t http_read_ahead_bytes;
  uint32_t reserved_flags;
  uint64_t reserved[4];
} ErikaFrameExportSessionOptions;

typedef struct ErikaFrameExportRequest {
  uint64_t position_millis;
  uint32_t max_width;
  uint32_t max_height;
  int32_t format; /* ErikaFrameExportFormat */
  uint32_t reserved_flags;
  uint64_t reserved[4];
} ErikaFrameExportRequest;

typedef enum ErikaStatus {
  ErikaStatus_Ok = 0,
  ErikaStatus_NullPointer = 1,
  ErikaStatus_InvalidUtf8 = 2,
  ErikaStatus_PlayerError = 3,
  ErikaStatus_Panic = 4,
  ErikaStatus_NoEvent = 5,
} ErikaStatus;

typedef enum ErikaState {
  ErikaState_Idle = 0,
  ErikaState_Opening = 1,
  ErikaState_Ready = 2,
  ErikaState_Playing = 3,
  ErikaState_Paused = 4,
  ErikaState_Stopped = 5,
  ErikaState_Closed = 6,
  ErikaState_Error = 7,
} ErikaState;

typedef enum ErikaEventKind {
  ErikaEventKind_None = 0,
  ErikaEventKind_StateChanged = 1,
  ErikaEventKind_DurationChanged = 2,
  ErikaEventKind_PositionChanged = 3,
  ErikaEventKind_TracksChanged = 4,
  ErikaEventKind_BufferingChanged = 5,
  ErikaEventKind_VideoParamsChanged = 6,
  ErikaEventKind_SurfaceAttached = 7,
  ErikaEventKind_SurfaceDetached = 8,
  ErikaEventKind_Error = 9,
  ErikaEventKind_TrackSelectionChanged = 10,
  ErikaEventKind_VideoDecoderChanged = 11,
  ErikaEventKind_AudioOutputChanged = 12,
  /* 13 is the hosts' own (a system media control asked for the previous or
   * next item); the engine never sends it. */
  /* The media played to its end on its own. Follows the Stopped state the
   * end brings; a stop asked for sends no Ended. */
  ErikaEventKind_Ended = 14,
} ErikaEventKind;

typedef enum ErikaTrackKind {
  ErikaTrackKind_Video = 0,
  ErikaTrackKind_Audio = 1,
  ErikaTrackKind_Subtitle = 2,
} ErikaTrackKind;

typedef enum ErikaTrackSource {
  ErikaTrackSource_Embedded = 0,
  ErikaTrackSource_External = 1,
} ErikaTrackSource;

typedef enum ErikaWgpuSurfaceKind {
  ErikaWgpuSurfaceKind_Unknown = 0,
  ErikaWgpuSurfaceKind_MacOsNsView = 1,
  ErikaWgpuSurfaceKind_MacOsCaMetalLayer = 2,
  ErikaWgpuSurfaceKind_IosUiView = 3,
  ErikaWgpuSurfaceKind_WindowsHwnd = 4,
  ErikaWgpuSurfaceKind_XlibWindow = 5,
  ErikaWgpuSurfaceKind_WaylandSurface = 6,
  ErikaWgpuSurfaceKind_AndroidNativeWindow = 7,
  ErikaWgpuSurfaceKind_OhosNativeWindow = 8,
} ErikaWgpuSurfaceKind;

typedef enum ErikaFlutterTextureKind {
  ErikaFlutterTextureKind_Unknown = 0,
  ErikaFlutterTextureKind_MacOsTextureRegistrar = 1,
  ErikaFlutterTextureKind_IosTextureRegistrar = 2,
  ErikaFlutterTextureKind_AndroidSurfaceTexture = 3,
  ErikaFlutterTextureKind_WindowsTextureRegistrar = 4,
  ErikaFlutterTextureKind_LinuxTextureRegistrar = 5,
} ErikaFlutterTextureKind;

typedef enum ErikaPresenterOutputMode {
  ErikaPresenterOutputMode_Sdr = 0,
  ErikaPresenterOutputMode_AppleEdr = 1,
  ErikaPresenterOutputMode_ExtendedLinear = 2,
  ErikaPresenterOutputMode_Auto = 3,
} ErikaPresenterOutputMode;

typedef enum ErikaActiveOutputEncoding {
  ErikaActiveOutputEncoding_SdrSrgb = 0,
  ErikaActiveOutputEncoding_AppleEdr = 1,
  ErikaActiveOutputEncoding_AndroidExtendedLinearScRgb = 2,
  ErikaActiveOutputEncoding_Hdr10Pq = 3,
  ErikaActiveOutputEncoding_LinuxExtendedLinearScRgb = 4,
} ErikaActiveOutputEncoding;

typedef enum ErikaOutputFallbackReason {
  ErikaOutputFallbackReason_None = 0,
  ErikaOutputFallbackReason_DisplayHdrUnsupported = 1,
  ErikaOutputFallbackReason_HybridCompositionRequired = 2,
  ErikaOutputFallbackReason_WgpuBackendNotVulkan = 3,
  ErikaOutputFallbackReason_Rgba16FloatSurfaceFormatUnavailable = 4,
  ErikaOutputFallbackReason_NativeWindowDataSpaceApiUnavailable = 5,
  ErikaOutputFallbackReason_ScrgbDataSpaceVerificationFailed = 6,
  ErikaOutputFallbackReason_SurfaceConfigureFailed = 7,
  ErikaOutputFallbackReason_LegacyAppleEdrUnsupported = 8,
} ErikaOutputFallbackReason;

typedef enum ErikaOutputSurfaceFormat {
  ErikaOutputSurfaceFormat_EightBitUnorm = 0,
  ErikaOutputSurfaceFormat_TenBitUnorm = 1,
  ErikaOutputSurfaceFormat_SixteenBitFloat = 2,
} ErikaOutputSurfaceFormat;

/* Upscaler modes. Values are grouped by family and stable: 1-15 ArtCNN,
 * 16-31 Anime4K, 32-47 spatial shaders, 48-63 platform scalers, 64 a
 * runtime-loaded network (erika_presenter_load_upscaler_model). Backends
 * that cannot run a mode keep native sampling and report Inactive. */
typedef enum ErikaLumaUpscalerMode {
  ErikaLumaUpscalerMode_Off = 0,
  ErikaLumaUpscalerMode_ArtCnnC4F16 = 1,
  ErikaLumaUpscalerMode_ArtCnnC4F32 = 2,
  ErikaLumaUpscalerMode_ArtCnnC4F16Ds = 3,
  ErikaLumaUpscalerMode_ArtCnnC4F16Dn = 4,
  ErikaLumaUpscalerMode_ArtCnnC4F32Ds = 5,
  ErikaLumaUpscalerMode_ArtCnnC4F32Dn = 6,
  ErikaLumaUpscalerMode_ArtCnnR8F64 = 7,
  ErikaLumaUpscalerMode_Anime4kS = 16,
  ErikaLumaUpscalerMode_Anime4kM = 17,
  ErikaLumaUpscalerMode_Anime4kL = 18,
  ErikaLumaUpscalerMode_Anime4kVl = 19,
  ErikaLumaUpscalerMode_Anime4kUl = 20,
  ErikaLumaUpscalerMode_Anime4kDenoiseS = 21,
  ErikaLumaUpscalerMode_Anime4kDenoiseM = 22,
  ErikaLumaUpscalerMode_Anime4kDenoiseL = 23,
  ErikaLumaUpscalerMode_Anime4kDenoiseVl = 24,
  ErikaLumaUpscalerMode_Anime4kDenoiseUl = 25,
  ErikaLumaUpscalerMode_Fsr1 = 32,
  ErikaLumaUpscalerMode_PlatformVideo = 48,
  ErikaLumaUpscalerMode_MetalFxSpatial = 49,
  ErikaLumaUpscalerMode_Custom = 64,
} ErikaLumaUpscalerMode;

typedef enum ErikaUpscalerBackendStatus {
  ErikaUpscalerBackendStatus_Off = 0,
  ErikaUpscalerBackendStatus_Inactive = 1,
  ErikaUpscalerBackendStatus_Building = 2,
  ErikaUpscalerBackendStatus_Scalar = 3,
  ErikaUpscalerBackendStatus_SimdgroupMatrix = 4,
  ErikaUpscalerBackendStatus_CooperativeMatrix = 5,
  ErikaUpscalerBackendStatus_LinalgMatrix = 6,
  ErikaUpscalerBackendStatus_VideoProcessor = 7,
  ErikaUpscalerBackendStatus_VideoToolbox = 8,
  ErikaUpscalerBackendStatus_MetalFx = 9,
  ErikaUpscalerBackendStatus_TensorOps = 10,
} ErikaUpscalerBackendStatus;

typedef enum ErikaVideoAlphaMode {
  ErikaVideoAlphaMode_Opaque = 0,
  ErikaVideoAlphaMode_PackedAlphaRight = 1,
} ErikaVideoAlphaMode;

typedef struct ErikaPresenterConfig {
  int32_t output_mode;
  float edr_headroom;
  int32_t luma_upscaler;
  int32_t video_alpha_mode;
} ErikaPresenterConfig;

#define ERIKA_SUBTITLE_OVERRIDE_FONT_SIZE_FIELDS (1u << 2)
#define ERIKA_SUBTITLE_OVERRIDE_FONT_NAME (1u << 3)
#define ERIKA_SUBTITLE_OVERRIDE_COLORS (1u << 4)
#define ERIKA_SUBTITLE_OVERRIDE_ATTRIBUTES (1u << 5)
#define ERIKA_SUBTITLE_OVERRIDE_BORDER (1u << 6)
#define ERIKA_SUBTITLE_OVERRIDE_ALIGNMENT (1u << 7)
#define ERIKA_SUBTITLE_OVERRIDE_MARGINS (1u << 8)
#define ERIKA_SUBTITLE_OVERRIDE_BLUR (1u << 11)
#define ERIKA_SUBTITLE_OVERRIDE_ALL                                              \
  (ERIKA_SUBTITLE_OVERRIDE_FONT_SIZE_FIELDS |                                   \
   ERIKA_SUBTITLE_OVERRIDE_FONT_NAME | ERIKA_SUBTITLE_OVERRIDE_COLORS |         \
   ERIKA_SUBTITLE_OVERRIDE_ATTRIBUTES | ERIKA_SUBTITLE_OVERRIDE_BORDER |        \
   ERIKA_SUBTITLE_OVERRIDE_ALIGNMENT | ERIKA_SUBTITLE_OVERRIDE_MARGINS |        \
   ERIKA_SUBTITLE_OVERRIDE_BLUR)

typedef struct ErikaSubtitleStyle {
  const char *font_family;
  const char *font_file_path;
  uint32_t primary_color_rgba;
  uint32_t outline_color_rgba;
  double font_size;
  double outline_width;
  bool bold;
  bool italic;
  bool underline;
  bool strike_out;
  double spacing;
  double scale_x_percent;
  double scale_y_percent;
  int32_t border_style;
  double shadow_depth;
  double blur;
  int32_t alignment;
  int32_t margin_left;
  int32_t margin_right;
  int32_t margin_vertical;
  uint32_t override_mask;
} ErikaSubtitleStyle;

typedef struct ErikaSurfaceOutputCapabilities {
  bool extended_linear;
  bool direct_composition;
  float desired_headroom;
  int32_t fallback_reason;
} ErikaSurfaceOutputCapabilities;

typedef struct ErikaUpscalerStatus {
  int32_t requested_mode;
  int32_t active_backend;
  uint64_t fallback_count;
  uint64_t upscaled_frames;
  uint64_t last_encode_micros;
  uint64_t last_gpu_micros;
} ErikaUpscalerStatus;

typedef struct ErikaOutputStatus {
  int32_t requested_mode;
  int32_t active_encoding;
  int32_t surface_format;
  int32_t native_data_space;
  float requested_headroom;
  float active_headroom;
  bool active_headroom_known;
  bool extended_linear_active;
  int32_t fallback_reason;
  uint64_t fallback_count;
  uint64_t data_space_failures;
  uint64_t headroom_updates;
  uint64_t extended_linear_frames;
} ErikaOutputStatus;

/* Renderer memory snapshot. Per-resource fields are allocations tracked by
 * one presenter. device_current_allocated_bytes is Metal's device-wide
 * process counter and may include allocations owned by other presenters. */
typedef struct ErikaPresenterResourceStatus {
  uint64_t device_current_allocated_bytes;
  uint64_t device_recommended_working_set_bytes;
  uint64_t drawable_estimated_bytes;
  uint64_t video_frame_bytes;
  uint64_t overlay_atlas_bytes;
  uint64_t danmaku_atlas_bytes;
  uint64_t danmaku_vertex_buffer_bytes;
  uint64_t upscaler_bytes;
  uint64_t renderer_tracked_bytes;
  uint64_t presenter_cpu_danmaku_atlas_bytes;
  uint32_t drawable_count;
  uint64_t output_mode_switches;
} ErikaPresenterResourceStatus;

typedef struct ErikaSubtitleMemoryFontStatus {
  uintptr_t registered_count;
  uintptr_t registered_bytes;
  uintptr_t selected_count;
  uint64_t generation;
  uint64_t *selected_ids;
} ErikaSubtitleMemoryFontStatus;

typedef struct ErikaSubtitleMemoryFontFace {
  uint32_t index;
  char *families_json;
  char *post_script_name;
  uint16_t weight;
  bool italic;
  bool monospaced;
} ErikaSubtitleMemoryFontFace;

typedef struct ErikaSubtitleMemoryFontInfo {
  uint64_t id;
  uintptr_t byte_len;
  ErikaSubtitleMemoryFontFace *faces;
  uintptr_t face_count;
} ErikaSubtitleMemoryFontInfo;

typedef struct ErikaDanmakuConfig {
  bool enabled;
  /* NipaPlay/Flutter logical danmaku font size. liberika uses the NipaPlay
   * default danmaku font and multiplies by the surface scale for glyph pixels. */
  float font_size;
  float opacity;
  float display_area;
  float scroll_duration_seconds;
  float scroll_speed_factor;
  float track_gap_ratio;
  float outline_width;
  float shadow_offset_x;
  float shadow_offset_y;
  bool merge_duplicates;
  bool allow_stacking;
  bool allow_scroll_overwrite;
  uint32_t max_quantity;
  uint32_t max_lines_per_mode;
  bool block_top;
  bool block_bottom;
  bool block_scroll;
  int32_t shadow_style;
} ErikaDanmakuConfig;

typedef struct ErikaDanmakuTrackInfo {
  uint64_t id;
  bool enabled;
  int64_t offset_micros;
  uintptr_t item_count;
  char *name;
  char *source;
} ErikaDanmakuTrackInfo;

typedef struct ErikaVideoParams {
  uint32_t width;
  uint32_t height;
  uint32_t primaries;
  uint32_t transfer;
} ErikaVideoParams;

typedef struct ErikaTrackCounts {
  uint32_t video;
  uint32_t audio;
  uint32_t subtitle;
} ErikaTrackCounts;

typedef struct ErikaTrackSelection {
  int64_t video;
  int64_t audio;
  int64_t subtitle;
} ErikaTrackSelection;

typedef struct ErikaTrackInfo {
  int64_t id;
  ErikaTrackKind kind;
  ErikaTrackSource source;
  bool selected;
  bool can_remove;
  char *title;
  char *language;
  char *codec;
  uint32_t width;
  uint32_t height;
  uint32_t sample_rate;
  uint32_t channels;
  char *pixel_format;
  char *sample_format;
  char *profile;
  int32_t level;
  uint64_t bit_rate;
  uint32_t frame_rate_numerator;
  uint32_t frame_rate_denominator;
} ErikaTrackInfo;

typedef struct ErikaEvent {
  ErikaEventKind kind;
  ErikaStatus status;
  ErikaState state;
  int64_t duration_micros;
  uint64_t position_micros;
  bool buffering;
  ErikaVideoParams video;
  ErikaTrackCounts tracks;
} ErikaEvent;

typedef struct ErikaPresenterStats {
  uint64_t decoded_video_frames;
  uint64_t rendered_video_frames;
  uint64_t rendered_test_frames;
  uint64_t pushed_audio_frames;
  uint64_t overlay_frames;
  uint64_t danmaku_frames;
  uint64_t danmaku_items;
  uint64_t import_failures;
  uint64_t render_failures;
  uint64_t audio_failures;
  uint64_t software_video_frames;
  uint64_t hardware_video_frames;
  uint64_t zero_copy_video_frames;
  uint64_t cpu_video_frame_fallbacks;
  uint64_t last_render_micros;
  uint64_t last_render_current_micros;
  uint64_t audio_clock_read_frames;
  uint64_t audio_clock_queued_frames;
  uint64_t audio_clock_underflow_frames;
  /* 0 stable, 1 disconnected, 2 recovering, 3 failed. */
  int32_t audio_recovery_state;
  int32_t audio_last_error_code;
  uint64_t audio_recovery_attempts;
  uint64_t audio_recovery_count;
  uint64_t audio_recovery_failures;
  uint64_t direct_zero_copy_video_frames;
  uint64_t shared_handle_video_frames;
  uint64_t hdr_source_frames;
  uint64_t hdr10_output_frames;
  uint64_t sdr_tonemap_frames;
  uint64_t hdr10_metadata_updates;
  uint64_t hdr10_metadata_failures;
  uint64_t hdr10_output_failures;
  bool hdr10_output_active;
  uint64_t video_frame_backpressure_drops;
} ErikaPresenterStats;

/* ===== ErikaHandle (pull model) ===== */

/* Lifecycle and thread-local error retrieval. erika_create never fails. */
ErikaHandle *erika_create(void);
void erika_destroy(ErikaHandle *handle);
char *erika_last_error_message(void);
void erika_string_free(char *value);

ErikaStatus erika_export_gif(
    const ErikaGifExportOptions *options,
    ErikaGifExportResult *out_result);
ErikaStatus erika_export_frame(
    const ErikaFrameExportOptions *options,
    ErikaFrameExportResult *out_result);
void erika_frame_export_result_free(ErikaFrameExportResult *result);
/* Synchronous: opening reads the container header and each frame call decodes
 * on the calling thread. Calls on one session are serialised; the session is
 * released with erika_frame_export_session_close (NULL is accepted), and no
 * call on it may be running or follow. *out_session is NULL after a failure. */
ErikaStatus erika_frame_export_session_open(
    const ErikaFrameExportSessionOptions *options,
    ErikaFrameExportSession **out_session);
ErikaStatus erika_frame_export_session_frame(
    ErikaFrameExportSession *session,
    const ErikaFrameExportRequest *request,
    ErikaFrameExportResult *out_result);
void erika_frame_export_session_close(ErikaFrameExportSession *session);

/* Playback control. uri is a local path or HTTP(S) URL; times are microseconds.
 * open() synchronously probes streams and transitions to Ready. */
ErikaStatus erika_open(ErikaHandle *handle, const char *uri);
ErikaStatus erika_open_with_headers(
    ErikaHandle *handle,
    const char *uri,
    const ErikaHttpHeader *headers,
    uintptr_t header_count);
/* open_with_options supersedes open_with_headers: headers plus per-request
 * tuning (currently the HTTP read-ahead window). */
ErikaStatus erika_open_with_options(
    ErikaHandle *handle,
    const char *uri,
    const ErikaOpenOptions *options);
/* play enqueues work; observe StateChanged/Error for the authoritative result. */
ErikaStatus erika_play(ErikaHandle *handle);
ErikaStatus erika_pause(ErikaHandle *handle);
ErikaStatus erika_stop(ErikaHandle *handle);
ErikaStatus erika_close(ErikaHandle *handle);
ErikaStatus erika_seek(ErikaHandle *handle, uint64_t position_micros);
/* Tracks and subtitles. Subtitle track id -1 disables subtitles.
 * erika_tracks uses the counted-array idiom; free each filled record with
 * erika_track_info_free. */
ErikaStatus erika_add_external_subtitle(
    ErikaHandle *handle,
    const char *uri,
    int64_t *out_track_id);
ErikaStatus erika_remove_subtitle_track(ErikaHandle *handle, int64_t track_id);
ErikaStatus erika_select_audio_track(ErikaHandle *handle, int64_t track_id);
ErikaStatus erika_select_subtitle_track(ErikaHandle *handle, int64_t track_id);
ErikaStatus erika_track_selection(
    ErikaHandle *handle,
    ErikaTrackSelection *out_selection);
ErikaStatus erika_tracks(
    ErikaHandle *handle,
    ErikaTrackInfo *out_tracks,
    uintptr_t capacity,
    uintptr_t *out_len);
void erika_track_info_free(ErikaTrackInfo *track);
void erika_danmaku_track_info_free(ErikaDanmakuTrackInfo *track);
/* State and non-blocking event polling (returns NoEvent when the queue is empty). */
ErikaStatus erika_state(ErikaHandle *handle, ErikaState *out_state);
ErikaStatus erika_poll_event(ErikaHandle *handle, ErikaEvent *out_event);

/* Host-managed surface attach. raw_layer is a CAMetalLayer* cast to uint64_t;
 * for wgpu, raw_window/raw_display are platform handles for the given kind. */
ErikaStatus erika_attach_metal_layer(
    ErikaHandle *handle,
    uint64_t raw_layer,
    uint32_t width,
    uint32_t height,
    double scale);

ErikaStatus erika_attach_wgpu_surface(
    ErikaHandle *handle,
    ErikaWgpuSurfaceKind kind,
    uint64_t raw_window,
    uint64_t raw_display,
    uint32_t width,
    uint32_t height,
    double scale);

ErikaStatus erika_attach_wgpu_surface_with_output_capabilities(
    ErikaHandle *handle,
    ErikaWgpuSurfaceKind kind,
    uint64_t raw_window,
    uint64_t raw_display,
    uint32_t width,
    uint32_t height,
    double scale,
    ErikaSurfaceOutputCapabilities output_capabilities);

ErikaStatus erika_attach_flutter_texture(
    ErikaHandle *handle,
    ErikaFlutterTextureKind kind,
    int64_t texture_id,
    uint32_t width,
    uint32_t height,
    double scale);

ErikaStatus erika_detach_surface(ErikaHandle *handle);

/* ===== ErikaPresenterHandle (push model) — macOS / iOS / Windows / Android / OpenHarmony ===== */

/* Lifecycle and configuration. A NULL return means creation failed; check
 * erika_last_error_message. Config selects output mode, EDR headroom, upscaler. */
ErikaPresenterHandle *erika_presenter_create(void);
ErikaPresenterHandle *erika_presenter_create_with_config(ErikaPresenterConfig config);
ErikaPresenterHandle *erika_presenter_create_with_output_mode(
    int32_t output_mode,
    float edr_headroom);
ErikaPresenterHandle *erika_presenter_create_with_output_mode_and_alpha(
    int32_t output_mode,
    float edr_headroom,
    int32_t video_alpha_mode);
void erika_presenter_destroy(ErikaPresenterHandle *handle);

/* Playback and runtime parameters. volume is 0.0–1.0; rate 1.0 is normal speed;
 * set_upscaler takes an ErikaLumaUpscalerMode. D3D11 runs every network mode,
 * FSR 1.0 and (on NVIDIA/Intel) PlatformVideo; Metal runs the network modes
 * and its platform scalers; wgpu/Vulkan runs the legacy ArtCNN modes. A
 * backend that cannot run a mode keeps native sampling and reports Inactive
 * (see erika_presenter_get_upscaler_status and the diagnostics JSON). */
ErikaStatus erika_presenter_open(ErikaPresenterHandle *handle, const char *uri);
ErikaStatus erika_presenter_open_with_headers(
    ErikaPresenterHandle *handle,
    const char *uri,
    const ErikaHttpHeader *headers,
    uintptr_t header_count);
/* open_with_options supersedes open_with_headers: headers plus per-request
 * tuning (currently the HTTP read-ahead window). */
ErikaStatus erika_presenter_open_with_options(
    ErikaPresenterHandle *handle,
    const char *uri,
    const ErikaOpenOptions *options);
/* play enqueues work; observe StateChanged/Error for the authoritative result. */
ErikaStatus erika_presenter_play(ErikaPresenterHandle *handle);
ErikaStatus erika_presenter_pause(ErikaPresenterHandle *handle);
ErikaStatus erika_presenter_stop(ErikaPresenterHandle *handle);
ErikaStatus erika_presenter_close(ErikaPresenterHandle *handle);
ErikaStatus erika_presenter_seek(ErikaPresenterHandle *handle, uint64_t position_micros);
ErikaStatus erika_presenter_set_playback_rate(ErikaPresenterHandle *handle, double rate);
ErikaStatus erika_presenter_set_volume(ErikaPresenterHandle *handle, double volume);
/* Silences the output (true) or restores it (false) without losing the
 * volume: set_volume while muted is kept and applied on unmute. */
ErikaStatus erika_presenter_set_muted(ErikaPresenterHandle *handle, bool muted);
ErikaStatus erika_presenter_set_upscaler(ErikaPresenterHandle *handle, int32_t mode);
/* Loads the network used by ErikaLumaUpscalerMode_Custom from memory: an
 * Erika .esr model (see crates/erika/assets/artcnn/export_artcnn_esr.py) or
 * an mpv hook shader of the FSRCNNX / Anime4K CNN dialect. Weights are never
 * bundled for such models; the host supplies them. Select the network with
 * erika_presenter_set_upscaler(handle, ErikaLumaUpscalerMode_Custom). */
ErikaStatus erika_presenter_load_upscaler_model(
    ErikaPresenterHandle *handle,
    const char *name,
    const uint8_t *data,
    uintptr_t data_len);
ErikaStatus erika_presenter_clear_upscaler_model(ErikaPresenterHandle *handle);
ErikaStatus erika_presenter_set_subtitle_scale(ErikaPresenterHandle *handle, double scale);
/* Shows subtitles later (positive delay_micros) or earlier (negative) than
 * their timestamps, embedded and external tracks alike; clamped to ten
 * minutes either way. 0 restores the timestamps. */
ErikaStatus erika_presenter_set_subtitle_delay(ErikaPresenterHandle *handle, int64_t delay_micros);
/* Where the next open on this presenter starts (microseconds) when its
 * options leave start_position_micros at 0, for hosts whose open path cannot
 * carry it. Taken by that open; 0 clears it. */
ErikaStatus erika_presenter_set_open_start_position(ErikaPresenterHandle *handle, uint64_t position_micros);
/* Fallback subtitle font. NULL or empty clears that half of the selection.
 * A container ASS script keeps its own font unless the font-name override bit
 * is passed through erika_presenter_set_subtitle_style. */
ErikaStatus erika_presenter_set_subtitle_font(
    ErikaPresenterHandle *handle,
    const char *family,
    const char *file_path);
ErikaStatus erika_presenter_register_subtitle_memory_font(
    ErikaPresenterHandle *handle,
    const uint8_t *data,
    uintptr_t data_len,
    uint64_t *out_font_id);
ErikaStatus erika_presenter_select_subtitle_memory_fonts(
    ErikaPresenterHandle *handle,
    const uint64_t *font_ids,
    uintptr_t font_count);
ErikaStatus erika_presenter_clear_subtitle_memory_fonts(ErikaPresenterHandle *handle);
ErikaStatus erika_presenter_get_subtitle_memory_font_status(
    ErikaPresenterHandle *handle,
    ErikaSubtitleMemoryFontStatus *out_status);
ErikaStatus erika_presenter_set_subtitle_style(
    ErikaPresenterHandle *handle,
    ErikaSubtitleStyle style);
void erika_subtitle_memory_font_status_free(
    ErikaSubtitleMemoryFontStatus *status);
ErikaStatus erika_presenter_get_subtitle_memory_font_info(
    ErikaPresenterHandle *handle,
    uint64_t font_id,
    ErikaSubtitleMemoryFontInfo *out_info);
void erika_subtitle_memory_font_info_free(ErikaSubtitleMemoryFontInfo *info);
ErikaStatus erika_presenter_set_output_headroom(
    ErikaPresenterHandle *handle,
    float headroom,
    bool known);
ErikaStatus erika_presenter_get_upscaler_status(
    ErikaPresenterHandle *handle,
    ErikaUpscalerStatus *out_status);
ErikaStatus erika_presenter_get_output_status(
    ErikaPresenterHandle *handle,
    ErikaOutputStatus *out_status);
ErikaStatus erika_presenter_get_resource_status(
    ErikaPresenterHandle *handle,
    ErikaPresenterResourceStatus *out_status);
ErikaStatus erika_presenter_add_external_subtitle(
    ErikaPresenterHandle *handle,
    const char *uri,
    int64_t *out_track_id);
ErikaStatus erika_presenter_remove_subtitle_track(
    ErikaPresenterHandle *handle,
    int64_t track_id);
ErikaStatus erika_presenter_select_audio_track(
    ErikaPresenterHandle *handle,
    int64_t track_id);
ErikaStatus erika_presenter_select_subtitle_track(
    ErikaPresenterHandle *handle,
    int64_t track_id);
/* Danmaku (bullet comments). load_* replaces danmaku with one anonymous track;
 * add_*_track builds a named multi-track list. Input is Bilibili XML (*_file,
 * by path/URL) or JSON (*_json, inline). offset_micros shifts one track's
 * timeline; the global offset shifts all. The inline JSON schema is documented
 * in docs/capi_reference.md; layout behavior is in docs/danmaku_architecture.md. */
ErikaStatus erika_presenter_load_danmaku_file(
    ErikaPresenterHandle *handle,
    const char *uri);
ErikaStatus erika_presenter_load_danmaku_json(
    ErikaPresenterHandle *handle,
    const char *json);
ErikaStatus erika_presenter_add_danmaku_track_file(
    ErikaPresenterHandle *handle,
    const char *uri,
    const char *name,
    int64_t offset_micros,
    uint64_t *out_track_id);
ErikaStatus erika_presenter_add_danmaku_track_json(
    ErikaPresenterHandle *handle,
    const char *json,
    const char *name,
    int64_t offset_micros,
    uint64_t *out_track_id);
ErikaStatus erika_presenter_remove_danmaku_track(
    ErikaPresenterHandle *handle,
    uint64_t track_id);
ErikaStatus erika_presenter_set_danmaku_track_enabled(
    ErikaPresenterHandle *handle,
    uint64_t track_id,
    bool enabled);
ErikaStatus erika_presenter_set_danmaku_track_offset(
    ErikaPresenterHandle *handle,
    uint64_t track_id,
    int64_t offset_micros);
ErikaStatus erika_presenter_set_danmaku_global_offset(
    ErikaPresenterHandle *handle,
    int64_t offset_micros);
ErikaStatus erika_presenter_danmaku_tracks(
    ErikaPresenterHandle *handle,
    ErikaDanmakuTrackInfo *out_tracks,
    uintptr_t capacity,
    uintptr_t *out_len);
ErikaStatus erika_presenter_clear_danmaku(ErikaPresenterHandle *handle);
ErikaStatus erika_presenter_set_danmaku_enabled(
    ErikaPresenterHandle *handle,
    bool enabled);
ErikaStatus erika_presenter_set_debug_hud_enabled(
    ErikaPresenterHandle *handle,
    bool enabled);
ErikaStatus erika_presenter_set_danmaku_config(
    ErikaPresenterHandle *handle,
    ErikaDanmakuConfig config);
ErikaStatus erika_presenter_set_danmaku_config_ptr(
    ErikaPresenterHandle *handle,
    const ErikaDanmakuConfig *config);
ErikaStatus erika_presenter_get_danmaku_config(
    ErikaPresenterHandle *handle,
    ErikaDanmakuConfig *out_config);
ErikaStatus erika_presenter_set_danmaku_font(
    ErikaPresenterHandle *handle,
    const char *family,
    const char *file_path);
ErikaStatus erika_presenter_set_danmaku_block_words_json(
    ErikaPresenterHandle *handle,
    const char *json);
ErikaStatus erika_presenter_set_danmaku_random_colors(
    ErikaPresenterHandle *handle,
    bool enabled);
ErikaStatus erika_presenter_track_selection(
    ErikaPresenterHandle *handle,
    ErikaTrackSelection *out_selection);
ErikaStatus erika_presenter_tracks(
    ErikaPresenterHandle *handle,
    ErikaTrackInfo *out_tracks,
    uintptr_t capacity,
    uintptr_t *out_len);

/* Surface and presentation. attach_metal_layer for macOS/iOS (CAMetalLayer*),
 * attach_windows_hwnd for Windows (wraps attach_wgpu_surface with WindowsHwnd:
 * hwnd = HWND, hinstance = HINSTANCE). The renderer backend (native Metal,
 * native D3D11, or wgpu) is chosen by presenter config, not the attach call.
 * Call resize_surface on any drawable-size or scale change. */
ErikaStatus erika_presenter_attach_metal_layer(
    ErikaPresenterHandle *handle,
    uint64_t raw_layer,
    uint32_t width,
    uint32_t height,
    double scale);

/* Flutter compositor texture surface. The registrar texture_id identifies the
 * surface; before every render_tick, select the host-owned GPU target with
 * set_flutter_texture_buffer. On Apple, raw_texture is an id<MTLTexture> using
 * BGRA8Unorm. The texture remains owned by the host. */
ErikaStatus erika_presenter_attach_flutter_texture(
    ErikaPresenterHandle *handle,
    ErikaFlutterTextureKind kind,
    int64_t texture_id,
    uint32_t width,
    uint32_t height,
    double scale);

ErikaStatus erika_presenter_set_flutter_texture_buffer(
    ErikaPresenterHandle *handle,
    uint64_t raw_texture,
    uint32_t width,
    uint32_t height);

/* Linux: XlibWindow takes the X11 Window ID in raw_window and Display* in
 * raw_display (screen 0). WaylandSurface takes wl_surface* and wl_display*.
 * Cast pointers through uintptr_t to uint64_t. Both handles must be non-null
 * and remain valid until detach_surface or presenter destruction completes.
 * Attach, resize, render and detach on the host window's event-loop thread.
 * Linux output is SDR. For Flutter use LinuxTextureRegistrar and copy the
 * composited frame with erika_presenter_copy_flutter_frame_rgba after ticking. */
ErikaStatus erika_presenter_attach_wgpu_surface(
    ErikaPresenterHandle *handle,
    ErikaWgpuSurfaceKind kind,
    uint64_t raw_window,
    uint64_t raw_display,
    uint32_t width,
    uint32_t height,
    double scale);

ErikaStatus erika_presenter_attach_wgpu_surface_with_output_capabilities(
    ErikaPresenterHandle *handle,
    ErikaWgpuSurfaceKind kind,
    uint64_t raw_window,
    uint64_t raw_display,
    uint32_t width,
    uint32_t height,
    double scale,
    ErikaSurfaceOutputCapabilities output_capabilities);

ErikaStatus erika_presenter_attach_windows_hwnd(
    ErikaPresenterHandle *handle,
    uint64_t hwnd,
    uint64_t hinstance,
    uint32_t width,
    uint32_t height,
    double scale);

/* Windows only. Returns an AddRef'd IUnknown for a DirectComposition swap
 * chain created by an attachment whose direct_composition capability is true.
 * The caller owns the returned COM reference and must Release it. */
ErikaStatus erika_presenter_windows_composition_swapchain_iunknown(
    ErikaPresenterHandle *handle,
    void **out_swapchain);

/* Windows only. Returns an AddRef'd IUnknown for the latest completed,
 * immutable SDR Flutter GPU frame. The caller owns the COM reference and
 * must Release it. The texture remains unchanged for its entire lifetime. */
ErikaStatus erika_presenter_windows_flutter_texture_iunknown(
    ErikaPresenterHandle *handle,
    void **out_texture);

ErikaStatus erika_presenter_resize_surface(
    ErikaPresenterHandle *handle,
    uint32_t width,
    uint32_t height,
    double scale);

ErikaStatus erika_presenter_detach_surface(ErikaPresenterHandle *handle);

/* Render loop and events. Call render_tick once per display frame from the
 * surface's display timer; time_seconds is the host display clock (presentation
 * timestamp) for the frame, used for vsync-quantized scheduling. out_stats may
 * be NULL. poll_event is non-blocking (NoEvent when idle). */
ErikaStatus erika_presenter_render_tick(
    ErikaPresenterHandle *handle,
    double time_seconds,
    ErikaPresenterStats *out_stats);
/* Optional display-target sampling. A non-NULL presentation_delay_seconds
 * points to the signed seconds from call entry to the display target (e.g.
 * CADisplayLink.targetTimestamp - CACurrentMediaTime()). It must be finite and
 * within +/-0.25 seconds. The value is copied before native work; no pointer is
 * retained. Danmaku, subtitles and render context sample the same playback
 * snapshot at that target without changing the playback clock. NULL preserves
 * render_tick's legacy sampling. Older native binaries may lack this symbol;
 * embedders should resolve it optionally and fall back to render_tick. */
ErikaStatus erika_presenter_render_tick_with_timing(
    ErikaPresenterHandle *handle,
    double time_seconds,
    const double *presentation_delay_seconds,
    ErikaPresenterStats *out_stats);
ErikaStatus erika_presenter_audio_only_tick(
    ErikaPresenterHandle *handle,
    ErikaPresenterStats *out_stats);
ErikaStatus erika_presenter_get_stats(
    ErikaPresenterHandle *handle,
    ErikaPresenterStats *out_stats);
ErikaStatus erika_presenter_poll_event(ErikaPresenterHandle *handle, ErikaEvent *out_event);

/* JSON bridge used by embedders whose platform channel already serializes
 * structured arguments. Returned strings are owned by liberika and must be
 * released with erika_string_free. poll_event_json returns NULL when idle.
 *
 * invoke_json is also the generic pass-through into liberika: method names
 * come from one dispatch table, and "listMethods" returns that table (name,
 * scope, arguments, result) so hosts can forward new capabilities without
 * code changes. Methods with scope "global" ("listMethods", "getLogs")
 * accept a NULL handle. The response is {"ok":true,"status":0,"value":...}
 * or {"ok":false,"status":n,"error":"..."}; an unknown method adds
 * "code":"unknown_method" and "method", malformed arguments JSON adds
 * "code":"invalid_arguments". */
char *erika_presenter_invoke_json(
    ErikaPresenterHandle *handle,
    const char *method,
    const char *arguments_json);
char *erika_presenter_render_tick_json(
    ErikaPresenterHandle *handle,
    double time_seconds);
char *erika_presenter_poll_event_json(ErikaPresenterHandle *handle);

/* ===== Diagnostics (JSON) =====
 * New diagnostic data is returned as JSON documents, never as new fields on
 * the structs above. Both functions may be missing from older native
 * libraries: resolve them optionally (dlsym / GetProcAddress) and treat a
 * missing symbol as "not supported". On Ok, *out_json receives a caller-owned
 * NUL-terminated UTF-8 document; free it with erika_string_free. It is NULL on
 * any other status. Each document has a "schema" number; fields are only
 * added within a schema. Layout: docs/capi_reference.md, "Diagnostics". */
typedef enum ErikaLogLevel {
  ErikaLogLevel_Trace = 0,
  ErikaLogLevel_Debug = 1,
  ErikaLogLevel_Info = 2,
  ErikaLogLevel_Warn = 3,
  ErikaLogLevel_Error = 4,
} ErikaLogLevel;

/* Process-wide log ring: liberika's operational diagnostics plus FFmpeg
 * warnings and errors. Returns the newest `limit` entries (0 = every retained
 * entry) at or above min_level (an ErikaLogLevel, or -1 for every level) with
 * seq >= since_seq (0 = from the oldest; pass the previous "nextSeq" to read
 * incrementally). Entries are oldest first and redacted: URL query strings
 * and user info, credential-like values and headers, the user's home
 * directory. The ring holds at most 2000 entries / 512 KiB. Needs no handle
 * and may be called from any thread. */
ErikaStatus erika_log_read_json(
    uint32_t limit,
    int32_t min_level,
    uint64_t since_seq,
    char **out_json);

/* One-call presenter snapshot: decoder and hardware-decode path, presenter
 * counters and stage durations, output/HDR, resources, upscaler, audio,
 * buffer depths, and timing (scheduler late drops, presentation cadence and
 * jitter, clock drift and corrections). Unknown values are null. It only
 * reads counters: no decoding or rendering, and it never waits on the
 * playback worker. Same threading rule as every other handle call. */
ErikaStatus erika_presenter_get_diagnostics_json(
    ErikaPresenterHandle *handle,
    char **out_json);

/* Screenshot: render the current composited frame (video + subtitle, no
 * danmaku) off-screen into a caller-allocated RGBA8 buffer at the requested
 * size. out_capacity must be >= width*height*4. Fails if no frame is
 * available yet. */
ErikaStatus erika_presenter_capture_frame_rgba(
    ErikaPresenterHandle *handle,
    uint32_t width,
    uint32_t height,
    uint8_t *out_rgba,
    uintptr_t out_capacity);

/* Off-screen host composition: same buffer, SDR output and error contract as
 * capture_frame_rgba, with enabled danmaku included (no debug HUD). No surface
 * or preceding render_tick is required. Danmaku follows the current playback
 * clock and is laid out at width*height pixels with scale factor 1. */
ErikaStatus erika_presenter_capture_frame_rgba_with_danmaku(
    ErikaPresenterHandle *handle,
    uint32_t width,
    uint32_t height,
    uint8_t *out_rgba,
    uintptr_t out_capacity);

/* Consume the latest Linux Flutter texture frame after render_tick. Includes
 * video, subtitles, danmaku and HUD. Returns NoEvent when no frame is ready.
 * The caller allocates at least surface_width*surface_height*4 bytes. */
ErikaStatus erika_presenter_copy_flutter_frame_rgba(
    ErikaPresenterHandle *handle, uint8_t *out_rgba, uintptr_t capacity,
    uint32_t *out_width, uint32_t *out_height);

typedef struct ErikaTextureFrame ErikaTextureFrame;
typedef enum ErikaExternalTextureKind {
    ErikaExternalTextureKind_Metal = 1,
    ErikaExternalTextureKind_VulkanOpaqueFd = 2,
} ErikaExternalTextureKind;
typedef enum ErikaExternalTextureFormat {
    ErikaExternalTextureFormat_Rgba8Unorm = 1,
} ErikaExternalTextureFormat;

typedef struct ErikaExternalTextureInfo {
    ErikaExternalTextureKind kind;
    ErikaExternalTextureFormat format;
    uint32_t width;
    uint32_t height;
    uint64_t native_handle;
    uint64_t device_id;
    uint64_t allocation_size;
    uint32_t memory_type_index;
    uint32_t vulkan_format;
    uint32_t vulkan_usage;
    uint32_t vulkan_tiling;
    uint8_t device_uuid[16];
    uint8_t driver_uuid[16];
} ErikaExternalTextureInfo;

/* Native, immutable SDR texture: video + subtitle + enabled danmaku, no HUD.
 * Select WgpuFallback. Supports Linux/Vulkan OPAQUE_FD and Apple/Metal. No
 * surface, Flutter registrar, CPU pixel readback or GPU texture copy. Waits
 * for producer GPU completion before returning. Unsupported backends and
 * sizes fail before any playback work.
 * Call once per host frame; also pumps audio, so render_tick is not required.
 * content_scale is physical pixels per logical point (as for resize_surface)
 * and sets danmaku size and speed. Danmaku is planned in the background like
 * on screen, so it can appear a few frames after a seek or size change.
 * NoEvent means no video yet. *out_frame is null on every non-Ok result.
 * Frames can outlive the presenter. Release only after consumer GPU work and
 * imported aliases are retired. Native handles from get_info are borrowed:
 * Metal is id<MTLTexture> on device_id (registryID).
 * Metal consumers may retain MTLTexture independently before releasing the
 * frame; that retained reference must cover all consumer GPU use.
 * Vulkan is an OPAQUE_FD (0 is valid), to be duplicated before import. Match
 * device AND driver UUIDs.
 * Vulkan: dedicated allocation, identical format/usage/tiling, 2D, 1 mip/layer/
 * sample, flags 0. Import allocation_size and memory_type_index. Acquire queue
 * ownership from EXTERNAL, old layout GENERAL, before reading. Read-only.
 * Pixels are sRGB-encoded RGBA in UNORM storage; the host compositor applies
 * any needed transfer conversion. */
ErikaStatus erika_presenter_export_frame_texture(
    ErikaPresenterHandle *handle, uint32_t width, uint32_t height,
    double content_scale, ErikaTextureFrame **out_frame);
/* Select the wgpu renderer, including on Apple where the default presenter
 * uses the native renderer. Returns NULL and sets last_error on failure. */
ErikaPresenterHandle *erika_presenter_create_for_texture_export(ErikaPresenterConfig config);
ErikaStatus erika_texture_frame_get_info(
    const ErikaTextureFrame *frame, ErikaExternalTextureInfo *out_info);
void erika_texture_frame_release(ErikaTextureFrame *frame);

#ifdef __cplusplus
}
#endif

#endif
