package com.flutter_rust_bridge.rust_lib_nipaplay;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

public final class RustLibNipaplayPlugin
    implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String CHANNEL_NAME = "nipaplay/next2_texture";
  private static final String TAG = "NipaPlayNext2";
  private static final int FALLBACK_SIZE = 512;
  private static final int MAX_DIMENSION = 16384;

  static {
    System.loadLibrary("rust_lib_nipaplay");
  }

  private MethodChannel channel;
  private TextureRegistry textureRegistry;
  private final Object lock = new Object();
  private final Map<String, SurfaceState> surfaces = new HashMap<>();
  private final ExecutorService renderExecutor =
      Executors.newSingleThreadExecutor(r -> new Thread(r, "nipaplay-next2-android-render"));
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private volatile boolean detached = false;

  private final Runnable ticker =
      new Runnable() {
        @Override
        public void run() {
          renderTick();
          if (textureRegistry != null) {
            mainHandler.postDelayed(this, 16);
          }
        }
      };

  private static final class SurfaceState {
    final String surfaceId;
    TextureRegistry.SurfaceTextureEntry textureEntry;
    Surface surface;
    int width;
    int height;
    long engineHandle;
    boolean initInProgress;
    boolean disposed;
    ByteBuffer frameBuffer;

    SurfaceState(String surfaceId, int width, int height) {
      this.surfaceId = surfaceId;
      this.width = width;
      this.height = height;
      this.engineHandle = 0L;
      this.initInProgress = false;
      this.disposed = false;
      this.frameBuffer = null;
    }
  }

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    detached = false;
    textureRegistry = binding.getTextureRegistry();
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    channel.setMethodCallHandler(this);
    mainHandler.post(ticker);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    detached = true;
    mainHandler.removeCallbacks(ticker);
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    releaseAllSurfaces();
    textureRegistry = null;
    renderExecutor.shutdown();
  }

  @Override
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    switch (call.method) {
      case "getTextureInfo":
        getTextureInfo(call.arguments, result);
        break;
      case "setFrame":
        setFrame(call.arguments, result);
        break;
      case "resetScene":
        resetScene(call.arguments, result);
        break;
      case "disposeTexture":
        disposeTexture(call.arguments, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private void getTextureInfo(Object arguments, MethodChannel.Result result) {
    if (detached || textureRegistry == null) {
      result.error("plugin_detached", "Texture registry unavailable", null);
      return;
    }
    final RequestedInfo request = parseRequestedInfo(arguments);
    final SurfaceState state;
    synchronized (lock) {
      state =
          surfaces.computeIfAbsent(
              request.surfaceId, id -> new SurfaceState(id, request.width, request.height));
      if (state.engineHandle != 0L
          && state.textureEntry != null
          && state.width == request.width
          && state.height == request.height
          && !state.initInProgress) {
        result.success(buildResponse(state, false));
        return;
      }
      if (state.initInProgress) {
        result.error("engine_init_busy", "Engine init already in progress", null);
        return;
      }
      state.initInProgress = true;
    }

    try {
      renderExecutor.execute(
          () -> {
            try {
              createOrResizeSurface(state, request);
              mainHandler.post(
                  () -> {
                    synchronized (lock) {
                      state.initInProgress = false;
                    }
                    if (detached) {
                      result.error("plugin_detached", "Plugin detached", null);
                    } else {
                      result.success(buildResponse(state, true));
                    }
                  });
            } catch (Exception e) {
              Log.e(TAG, "getTextureInfo failed", e);
              mainHandler.post(
                  () -> {
                    synchronized (lock) {
                      state.initInProgress = false;
                    }
                    result.error("engine_init_failed", e.getMessage(), null);
                  });
            }
          });
    } catch (RejectedExecutionException e) {
      synchronized (lock) {
        state.initInProgress = false;
      }
      result.error("plugin_detached", "Renderer executor unavailable", null);
    }
  }

  private void createOrResizeSurface(SurfaceState state, RequestedInfo request) {
    TextureRegistry.SurfaceTextureEntry oldEntry = state.textureEntry;
    Surface oldSurface = state.surface;

    final TextureRegistry.SurfaceTextureEntry textureEntry = textureRegistry.createSurfaceTexture();
    textureEntry.surfaceTexture().setDefaultBufferSize(request.width, request.height);
    final Surface surface = new Surface(textureEntry.surfaceTexture());

    long handle = state.engineHandle;
    boolean engineCreated = false;
    if (handle == 0L) {
      handle = nativeNext2EngineCreate(request.width, request.height);
      engineCreated = true;
    } else {
      int resizeOk = nativeNext2EngineResize(handle, request.width, request.height);
      if (resizeOk == 0) {
        nativeNext2EngineDispose(handle);
        handle = nativeNext2EngineCreate(request.width, request.height);
        engineCreated = true;
      }
    }
    if (handle == 0L) {
      textureEntry.release();
      surface.release();
      throw new IllegalStateException("next2_engine_create returned 0");
    }

    int attached =
        nativeNext2AttachSurface(handle, surface, request.width, request.height) ? 1 : 0;
    if (attached == 0) {
      textureEntry.release();
      surface.release();
      if (engineCreated) {
        nativeNext2EngineDispose(handle);
      }
      throw new IllegalStateException("nativeNext2AttachSurface failed");
    }

    synchronized (lock) {
      if (state.disposed) {
        textureEntry.release();
        surface.release();
        nativeNext2EngineDispose(handle);
        return;
      }
      state.engineHandle = handle;
      state.textureEntry = textureEntry;
      state.surface = surface;
      state.width = request.width;
      state.height = request.height;
    }

    if (oldSurface != null) {
      oldSurface.release();
    }
    if (oldEntry != null) {
      oldEntry.release();
    }
  }

  private void setFrame(Object arguments, MethodChannel.Result result) {
    if (!(arguments instanceof Map)) {
      result.error("invalid_arguments", "Missing arguments", null);
      return;
    }
    Map<?, ?> args = (Map<?, ?>) arguments;
    long handle = readLong(args.get("engineHandle"), 0L);
    String frameJson = args.get("frameJson") instanceof String ? (String) args.get("frameJson") : null;
    if (handle == 0L || frameJson == null) {
      result.error("invalid_arguments", "Missing engineHandle/frameJson", null);
      return;
    }
    float fontSize = readFloat(args.get("fontSize"), 24.0f);
    float outlineWidth = readFloat(args.get("outlineWidth"), 1.0f);
    int shadowStyle = readInt(args.get("shadowStyle"), 1);
    float opacity = readFloat(args.get("opacity"), 1.0f);
    int ok = nativeNext2EngineSetFrame(handle, frameJson, fontSize, outlineWidth, shadowStyle, opacity);
    result.success(ok != 0);
  }

  private void resetScene(Object arguments, MethodChannel.Result result) {
    if (!(arguments instanceof Map)) {
      result.error("invalid_arguments", "Missing arguments", null);
      return;
    }
    Map<?, ?> args = (Map<?, ?>) arguments;
    long handle = readLong(args.get("engineHandle"), 0L);
    if (handle == 0L) {
      result.error("invalid_arguments", "Missing engineHandle", null);
      return;
    }
    int ok = nativeNext2EngineResetScene(handle);
    result.success(ok != 0);
  }

  private void disposeTexture(Object arguments, MethodChannel.Result result) {
    final String surfaceId = parseSurfaceId(arguments);
    SurfaceState removed;
    synchronized (lock) {
      removed = surfaces.remove(surfaceId);
      if (removed != null) {
        removed.disposed = true;
      }
    }
    if (removed != null) {
      if (removed.surface != null) {
        removed.surface.release();
      }
      if (removed.textureEntry != null) {
        removed.textureEntry.release();
      }
      if (removed.engineHandle != 0L) {
        nativeNext2EngineDispose(removed.engineHandle);
      }
    }
    result.success(null);
  }

  private void releaseAllSurfaces() {
    final Map<String, SurfaceState> snapshot;
    synchronized (lock) {
      snapshot = new HashMap<>(surfaces);
      surfaces.clear();
    }
    for (SurfaceState state : snapshot.values()) {
      if (state.surface != null) {
        state.surface.release();
      }
      if (state.textureEntry != null) {
        state.textureEntry.release();
      }
      if (state.engineHandle != 0L) {
        nativeNext2EngineDispose(state.engineHandle);
      }
    }
  }

  private void renderTick() {
    if (textureRegistry == null || detached) {
      return;
    }
    final Map<String, SurfaceState> snapshot;
    synchronized (lock) {
      snapshot = new HashMap<>(surfaces);
    }
    for (SurfaceState state : snapshot.values()) {
      if (state.engineHandle == 0L || state.surface == null || state.textureEntry == null) {
        continue;
      }
      if (!nativeNext2EnginePollFrameReady(state.engineHandle)) {
        continue;
      }
      int size = state.width * state.height * 4;
      if (size <= 0) {
        continue;
      }
      if (state.frameBuffer == null || state.frameBuffer.capacity() != size) {
        state.frameBuffer = ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder());
      }
      state.frameBuffer.clear();
      long packed = nativeNext2EngineCopyBgraFrame(state.engineHandle, state.frameBuffer, size);
      int outW = (int) (packed >>> 32);
      int outH = (int) (packed & 0xFFFFFFFFL);
      if (packed == 0L || outW <= 0 || outH <= 0) {
        continue;
      }

      state.frameBuffer.position(0);
      Bitmap bitmap = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888);
      bitmap.copyPixelsFromBuffer(state.frameBuffer);

      Canvas canvas;
      try {
        canvas = state.surface.lockCanvas(null);
      } catch (Exception e) {
        bitmap.recycle();
        continue;
      }
      try {
        canvas.drawColor(android.graphics.Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR);
        canvas.drawBitmap(bitmap, null, new Rect(0, 0, state.width, state.height), new Paint());
      } finally {
        state.surface.unlockCanvasAndPost(canvas);
        bitmap.recycle();
      }
    }
  }

  private static final class RequestedInfo {
    final String surfaceId;
    final int width;
    final int height;

    RequestedInfo(String surfaceId, int width, int height) {
      this.surfaceId = surfaceId;
      this.width = width;
      this.height = height;
    }
  }

  private RequestedInfo parseRequestedInfo(Object arguments) {
    int width = FALLBACK_SIZE;
    int height = FALLBACK_SIZE;
    String surfaceId = "default";
    if (arguments instanceof Map) {
      Map<?, ?> args = (Map<?, ?>) arguments;
      width = clampInt(readInt(args.get("width"), FALLBACK_SIZE), 1, MAX_DIMENSION);
      height = clampInt(readInt(args.get("height"), FALLBACK_SIZE), 1, MAX_DIMENSION);
      surfaceId = parseSurfaceId(arguments);
    }
    return new RequestedInfo(surfaceId, width, height);
  }

  private String parseSurfaceId(Object arguments) {
    if (arguments instanceof Map) {
      Map<?, ?> args = (Map<?, ?>) arguments;
      Object value = args.get("surfaceId");
      if (value instanceof String && !((String) value).isEmpty()) {
        return (String) value;
      }
      if (value instanceof Number) {
        return String.valueOf(((Number) value).longValue());
      }
    }
    return "default";
  }

  private Map<String, Object> buildResponse(SurfaceState state, boolean isNewEngine) {
    final Map<String, Object> response = new HashMap<>();
    response.put("textureId", state.textureEntry.id());
    response.put("engineHandle", state.engineHandle);
    response.put("width", state.width);
    response.put("height", state.height);
    response.put("isNewEngine", isNewEngine);
    return response;
  }

  private static int clampInt(int value, int min, int max) {
    return Math.max(min, Math.min(max, value));
  }

  private static int readInt(Object value, int fallback) {
    if (value instanceof Number) {
      return ((Number) value).intValue();
    }
    if (value instanceof String) {
      try {
        return Integer.parseInt((String) value);
      } catch (Exception ignored) {
      }
    }
    return fallback;
  }

  private static long readLong(Object value, long fallback) {
    if (value instanceof Number) {
      return ((Number) value).longValue();
    }
    if (value instanceof String) {
      try {
        return Long.parseLong((String) value);
      } catch (Exception ignored) {
      }
    }
    return fallback;
  }

  private static float readFloat(Object value, float fallback) {
    if (value instanceof Number) {
      return ((Number) value).floatValue();
    }
    if (value instanceof String) {
      try {
        return Float.parseFloat((String) value);
      } catch (Exception ignored) {
      }
    }
    return fallback;
  }

  private static native long nativeNext2EngineCreate(int width, int height);

  private static native int nativeNext2EngineResize(long handle, int width, int height);

  private static native void nativeNext2EngineDispose(long handle);

  private static native boolean nativeNext2EnginePollFrameReady(long handle);

  private static native int nativeNext2EngineSetFrame(
      long handle, String frameJson, float fontSize, float outlineWidth, int shadowStyle, float opacity);

  private static native int nativeNext2EngineResetScene(long handle);

  private static native long nativeNext2EngineCopyBgraFrame(
      long handle, ByteBuffer outBuffer, int outLen);

  private static native boolean nativeNext2AttachSurface(
      long handle, Surface surface, int width, int height);
}
