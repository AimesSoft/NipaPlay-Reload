package com.flutter_rust_bridge.rust_lib_nipaplay;

import android.graphics.SurfaceTexture;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
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

  private static final class SurfaceState {
    final String surfaceId;
    TextureRegistry.SurfaceTextureEntry textureEntry;
    Surface surface;
    int width;
    int height;
    long engineHandle;
    boolean initInProgress;
    boolean disposed;
    final List<PendingResult> pendingResults = new ArrayList<>();

    SurfaceState(String surfaceId, int width, int height) {
      this.surfaceId = surfaceId;
      this.width = width;
      this.height = height;
      this.engineHandle = 0L;
      this.initInProgress = false;
      this.disposed = false;
    }
  }

  private static final class SurfaceCreateResult {
    final TextureRegistry.SurfaceTextureEntry textureEntry;
    final Surface surface;
    final String error;

    SurfaceCreateResult(
        TextureRegistry.SurfaceTextureEntry textureEntry, Surface surface, String error) {
      this.textureEntry = textureEntry;
      this.surface = surface;
      this.error = error;
    }

    static SurfaceCreateResult error(String message) {
      return new SurfaceCreateResult(null, null, message);
    }
  }

  private static final class PendingResult {
    final RequestedInfo request;
    final MethodChannel.Result result;

    PendingResult(RequestedInfo request, MethodChannel.Result result) {
      this.request = request;
      this.result = result;
    }
  }

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    detached = false;
    textureRegistry = binding.getTextureRegistry();
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    detached = true;
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
        result.success(buildResponse(state, state.textureEntry, false));
        return;
      }
      state.pendingResults.add(new PendingResult(request, result));
      if (state.initInProgress) {
        return;
      }
      state.initInProgress = true;
    }

    try {
      renderExecutor.execute(() -> initSurface(request, state));
    } catch (RejectedExecutionException e) {
      final List<MethodChannel.Result> callbacks = new ArrayList<>();
      synchronized (lock) {
        state.initInProgress = false;
        for (PendingResult pending : state.pendingResults) {
          callbacks.add(pending.result);
        }
        state.pendingResults.clear();
      }
      mainHandler.post(
          () -> {
            for (MethodChannel.Result callback : callbacks) {
              callback.error("plugin_detached", "Renderer executor unavailable", null);
            }
          });
    }
  }

  private void initSurface(RequestedInfo request, SurfaceState state) {
    try {
      createOrResizeSurface(state, request);
      final List<MethodChannel.Result> callbacks = new ArrayList<>();
      RequestedInfo nextRequest = null;
      Map<String, Object> response = null;

      synchronized (lock) {
        state.initInProgress = false;
        final TextureRegistry.SurfaceTextureEntry textureEntry = state.textureEntry;
        if (state.disposed || textureEntry == null || state.surface == null || state.engineHandle == 0L) {
          throw new IllegalStateException("surface became unavailable during init");
        }
        response = buildResponse(state, textureEntry, true);
        if (!state.pendingResults.isEmpty()) {
          final List<PendingResult> remaining = new ArrayList<>();
          for (PendingResult pending : state.pendingResults) {
            if (pending.request.width == state.width
                && pending.request.height == state.height
                && pending.request.surfaceId.equals(state.surfaceId)) {
              callbacks.add(pending.result);
            } else {
              remaining.add(pending);
            }
          }
          state.pendingResults.clear();
          state.pendingResults.addAll(remaining);
          if (!state.pendingResults.isEmpty()) {
            nextRequest = state.pendingResults.get(state.pendingResults.size() - 1).request;
            state.initInProgress = true;
          }
        }
      }

      final Map<String, Object> successResponse = response;
      final RequestedInfo followRequest = nextRequest;
      mainHandler.post(
          () -> {
            final boolean stillAlive;
            synchronized (lock) {
              stillAlive = !detached && !state.disposed;
            }
            if (!stillAlive) {
              for (MethodChannel.Result callback : callbacks) {
                callback.error(
                    detached ? "plugin_detached" : "surface_disposed",
                    detached ? "Plugin detached" : "surface disposed",
                    null);
              }
            } else {
              for (MethodChannel.Result callback : callbacks) {
                callback.success(successResponse);
              }
            }
          });

      if (followRequest != null) {
        renderExecutor.execute(() -> initSurface(followRequest, state));
      }
    } catch (Exception e) {
      Log.e(TAG, "getTextureInfo failed", e);
      final List<MethodChannel.Result> callbacks = new ArrayList<>();
      synchronized (lock) {
        state.initInProgress = false;
        for (PendingResult pending : state.pendingResults) {
          callbacks.add(pending.result);
        }
        state.pendingResults.clear();
      }
      mainHandler.post(
          () -> {
            for (MethodChannel.Result callback : callbacks) {
              callback.error("engine_init_failed", e.getMessage(), null);
            }
          });
    }
  }

  private void createOrResizeSurface(SurfaceState state, RequestedInfo request) {
    TextureRegistry.SurfaceTextureEntry oldEntry = state.textureEntry;
    Surface oldSurface = state.surface;

    SurfaceCreateResult createResult = createSurfaceOnMainThread(request.width, request.height);
    if (createResult.textureEntry == null || createResult.surface == null) {
      throw new IllegalStateException(
          createResult.error != null ? createResult.error : "Surface creation failed");
    }
    final TextureRegistry.SurfaceTextureEntry textureEntry = createResult.textureEntry;
    final Surface surface = createResult.surface;

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
      releaseSurfaceResourcesOnMainThread(surface, textureEntry);
      throw new IllegalStateException("next2_engine_create returned 0");
    }

    boolean attached = nativeNext2AttachSurface(handle, surface, request.width, request.height);
    if (!attached) {
      releaseSurfaceResourcesOnMainThread(surface, textureEntry);
      if (engineCreated) {
        nativeNext2EngineDispose(handle);
      }
      throw new IllegalStateException("nativeNext2AttachSurface failed");
    }

    synchronized (lock) {
      if (state.disposed) {
        releaseSurfaceResourcesOnMainThread(surface, textureEntry);
        nativeNext2EngineDispose(handle);
        return;
      }
      state.engineHandle = handle;
      state.textureEntry = textureEntry;
      state.surface = surface;
      state.width = request.width;
      state.height = request.height;
    }

    releaseOldResourcesOnMainThread(oldSurface, oldEntry);
  }

  private SurfaceCreateResult createSurfaceOnMainThread(int width, int height) {
    if (Looper.myLooper() == Looper.getMainLooper()) {
      return createSurface(width, height);
    }
    final SurfaceCreateResult[] holder = new SurfaceCreateResult[1];
    final CountDownLatch latch = new CountDownLatch(1);
    mainHandler.post(
        () -> {
          try {
            holder[0] = createSurface(width, height);
          } catch (RuntimeException e) {
            holder[0] = SurfaceCreateResult.error("create_surface_exception: " + e.getMessage());
          } finally {
            latch.countDown();
          }
        });
    try {
      latch.await();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return SurfaceCreateResult.error("create_surface_interrupted");
    }
    if (holder[0] == null) {
      return SurfaceCreateResult.error("create_surface_failed");
    }
    return holder[0];
  }

  private void releaseSurfaceResourcesOnMainThread(
      Surface surface, TextureRegistry.SurfaceTextureEntry textureEntry) {
    if (surface == null && textureEntry == null) {
      return;
    }
    if (Looper.myLooper() == Looper.getMainLooper()) {
      if (surface != null) {
        surface.release();
      }
      if (textureEntry != null) {
        textureEntry.release();
      }
      return;
    }
    mainHandler.post(
        () -> {
          if (surface != null) {
            surface.release();
          }
          if (textureEntry != null) {
            textureEntry.release();
          }
        });
  }

  private SurfaceCreateResult createSurface(int width, int height) {
    if (textureRegistry == null) {
      return SurfaceCreateResult.error("Texture registry unavailable");
    }
    TextureRegistry.SurfaceTextureEntry textureEntry = textureRegistry.createSurfaceTexture();
    SurfaceTexture surfaceTexture = textureEntry.surfaceTexture();
    surfaceTexture.setDefaultBufferSize(width, height);
    Surface surface = new Surface(surfaceTexture);
    return new SurfaceCreateResult(textureEntry, surface, null);
  }

  private void releaseOldResourcesOnMainThread(Surface oldSurface, TextureRegistry.SurfaceTextureEntry oldEntry) {
    releaseSurfaceResourcesOnMainThread(oldSurface, oldEntry);
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
    final List<MethodChannel.Result> pendingCallbacks = new ArrayList<>();
    synchronized (lock) {
      removed = surfaces.remove(surfaceId);
      if (removed != null) {
        removed.disposed = true;
        for (PendingResult pending : removed.pendingResults) {
          pendingCallbacks.add(pending.result);
        }
        removed.pendingResults.clear();
      }
    }
    if (!pendingCallbacks.isEmpty()) {
      mainHandler.post(
          () -> {
            for (MethodChannel.Result callback : pendingCallbacks) {
              callback.error("surface_disposed", "surface disposed", null);
            }
          });
    }
    if (removed != null) {
      releaseSurfaceResourcesOnMainThread(removed.surface, removed.textureEntry);
      removed.surface = null;
      removed.textureEntry = null;
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
      state.disposed = true;
      state.pendingResults.clear();
      releaseSurfaceResourcesOnMainThread(state.surface, state.textureEntry);
      state.surface = null;
      state.textureEntry = null;
      if (state.engineHandle != 0L) {
        nativeNext2EngineDispose(state.engineHandle);
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

  private Map<String, Object> buildResponse(
      SurfaceState state, TextureRegistry.SurfaceTextureEntry textureEntry, boolean isNewEngine) {
    final Map<String, Object> response = new HashMap<>();
    response.put("textureId", textureEntry.id());
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

  private static native int nativeNext2EngineSetFrame(
      long handle, String frameJson, float fontSize, float outlineWidth, int shadowStyle, float opacity);

  private static native int nativeNext2EngineResetScene(long handle);

  private static native boolean nativeNext2AttachSurface(
      long handle, Surface surface, int width, int height);
}
