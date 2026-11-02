import {
  AbilityAware,
  AbilityPluginBinding,
  EventChannel,
  EventSink,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  StandardMethodCodec,
  SurfaceTextureEntry,
} from '@ohos/flutter_ohos';
import { common, UIAbility } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { image } from '@kit.ImageKit';
import erikaNative from 'liberika_flutter.so';

interface NativeResponse {
  ok: boolean;
  status: number;
  error?: string;
  value?: ESObject;
}

interface ErikaTexture {
  entry: SurfaceTextureEntry;
  surfaceId: number;
  width: number;
  height: number;
  scale: number;
  playerId: number;
}

interface ErikaMediaMetadata {
  title: string;
  artist?: string;
  album?: string;
  artwork?: Uint8Array;
}

interface ErikaMediaState {
  playbackState: number;
  positionMicros: number;
  durationMicros: number;
  playbackRate: number;
}

interface ErikaMediaNavigation {
  previousEnabled: boolean;
  nextEnabled: boolean;
}

const PLAYER_CHANNEL: string = 'erika_flutter/player';
const EVENT_CHANNEL: string = 'erika_flutter/events';
const FRAME_INTERVAL_MS: number = 16;
const STATE_CHANGED_EVENT_KIND: number = 1;
const DURATION_CHANGED_EVENT_KIND: number = 2;
const POSITION_CHANGED_EVENT_KIND: number = 3;
const SYSTEM_MEDIA_NAVIGATION_EVENT_KIND: number = 13;
const PLAYING_STATE: number = 3;
const PAUSED_STATE: number = 4;
const STOPPED_STATE: number = 5;
const CLOSED_STATE: number = 6;
const ERROR_STATE: number = 7;

export default class ErikaFlutterPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private binding: FlutterPluginBinding | null = null;
  private ability: UIAbility | null = null;
  private methodChannel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private eventSink: EventSink | null = null;
  private players: Set<number> = new Set();
  private textures: Map<number, ErikaTexture> = new Map();
  private mediaMetadata: Map<number, ErikaMediaMetadata> = new Map();
  private mediaStates: Map<number, ErikaMediaState> = new Map();
  private mediaNavigation: Map<number, ErikaMediaNavigation> = new Map();
  private currentPlayerId: number = 0;
  private currentSession: avSession.AVSession | null = null;
  private sessionPromise: Promise<avSession.AVSession | null> | null = null;
  private sessionGeneration: number = 0;
  private frameTimer: number = -1;

  getUniqueClassName(): string {
    return 'ErikaFlutterPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.binding = binding;
    const messenger = binding.getBinaryMessenger();
    this.methodChannel = new MethodChannel(
      messenger,
      PLAYER_CHANNEL,
      StandardMethodCodec.INSTANCE,
    );
    this.methodChannel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(
      messenger,
      EVENT_CHANNEL,
      StandardMethodCodec.INSTANCE,
    );
    this.eventChannel.setStreamHandler({
      onListen: (_args: ESObject, sink: EventSink): void => {
        this.eventSink = sink;
        this.drainAllEvents();
      },
      onCancel: (_args: ESObject): void => {
        this.eventSink = null;
      },
    });
    this.startFrameLoop();
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.stopFrameLoop();
    this.textures.forEach((texture: ErikaTexture, textureId: number): void => {
      if (texture.playerId > 0) {
        erikaNative.nativeDetachSurface(texture.playerId);
      }
      this.binding?.getTextureRegistry()?.unregisterTexture(textureId);
    });
    this.textures.clear();
    this.players.forEach((playerId: number): void => {
      erikaNative.nativeDestroy(playerId);
    });
    this.players.clear();
    this.mediaMetadata.clear();
    this.mediaStates.clear();
    this.mediaNavigation.clear();
    this.currentPlayerId = 0;
    this.destroyAVSession();
    this.methodChannel?.setMethodCallHandler(null);
    this.eventChannel?.setStreamHandler(null);
    this.methodChannel = null;
    this.eventChannel = null;
    this.eventSink = null;
    this.binding = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
  }

  onDetachedFromAbility(): void {
    this.ability = null;
    this.destroyAVSession();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const args: Map<string, ESObject> = call.args as Map<string, ESObject>;
    if (call.method === 'create') {
      this.createPlayer(args, result);
      return;
    }
    if (call.method === 'dispose') {
      this.disposePlayer(args, result);
      return;
    }
    if (call.method === 'createTexture') {
      this.createTexture(args, result);
      return;
    }
    if (call.method === 'resizeTexture') {
      this.resizeTexture(args, result);
      return;
    }
    if (call.method === 'releaseTexture') {
      this.releaseTexture(args, result);
      return;
    }
    if (call.method === 'attachView') {
      this.attachView(args, result);
      return;
    }
    if (call.method === 'detachView') {
      this.detachView(args, result);
      return;
    }
    if (call.method === 'screenshot') {
      this.captureFrame(args, result);
      return;
    }
    if (call.method === 'setMediaMetadata') {
      this.setMediaMetadata(args, result);
      return;
    }
    if (call.method === 'setSystemMediaNavigation') {
      this.setSystemMediaNavigation(args, result);
      return;
    }
    if (call.method === 'open') {
      this.openPlayer(args, result);
      return;
    }
    if (call.method === 'registerSubtitleMemoryFont') {
      this.registerSubtitleMemoryFont(args, result);
      return;
    }
    if (this.isNativePlayerMethod(call.method)) {
      this.invokePlayer(call.method, args, result);
      return;
    }
    result.notImplemented();
  }

  private createPlayer(args: Map<string, ESObject>, result: MethodResult): void {
    const outputMode = this.numberArg(args, 'outputMode', 0);
    const headroom = this.numberArg(
      args,
      'edrHeadroom',
      outputMode === 2 ? 4.0 : 1.0,
    );
    const upscaler = this.numberArg(args, 'upscaler', 0);
    const videoAlphaMode = this.numberArg(args, 'videoAlphaMode', 0);
    const playerId = erikaNative.nativeCreate(outputMode, headroom, upscaler, videoAlphaMode) as number;
    if (playerId <= 0) {
      result.error(
        'ERIKA_ERROR',
        'Erika OpenHarmony presenter creation failed: ' +
          (erikaNative.nativeLastError() as string),
        null,
      );
      return;
    }
    this.players.add(playerId);
    this.mediaStates.set(playerId, {
      playbackState: 0,
      positionMicros: 0,
      durationMicros: 0,
      playbackRate: 1.0,
    });
    this.mediaNavigation.set(playerId, {
      previousEnabled: false,
      nextEnabled: false,
    });
    result.success(playerId);
  }

  private disposePlayer(args: Map<string, ESObject>, result: MethodResult): void {
    const playerId = this.numberArg(args, 'playerId', 0);
    this.textures.forEach((texture: ErikaTexture): void => {
      if (texture.playerId === playerId) {
        erikaNative.nativeDetachSurface(playerId);
        texture.playerId = 0;
      }
    });
    if (this.players.delete(playerId)) {
      erikaNative.nativeDestroy(playerId);
    }
    this.mediaMetadata.delete(playerId);
    this.mediaStates.delete(playerId);
    this.mediaNavigation.delete(playerId);
    if (this.currentPlayerId === playerId) {
      this.currentPlayerId = 0;
      this.deactivateAVSession();
    }
    result.success(null);
  }

  private openPlayer(args: Map<string, ESObject>, result: MethodResult): void {
    const metadataValue: ESObject = args.get('metadata');
    let metadata: ErikaMediaMetadata | null = null;
    if (metadataValue !== undefined && metadataValue !== null) {
      metadata = this.parseMediaMetadata(metadataValue);
      if (metadata === null) {
        result.error('INVALID_ARGUMENT', 'metadata.title is required', null);
        return;
      }
    }
    const playerId = this.numberArg(args, 'playerId', 0);
    const nativeArgs: Map<string, ESObject> = new Map<string, ESObject>(args);
    nativeArgs.delete('metadata');
    if (!this.invokePlayerNative('open', nativeArgs, result)) {
      return;
    }
    const state = this.mediaStates.get(playerId);
    if (state !== undefined) {
      state.playbackState = 0;
      state.positionMicros = 0;
      state.durationMicros = 0;
    }
    if (metadata !== null) {
      this.mediaMetadata.set(playerId, metadata);
      if (this.currentPlayerId === playerId) {
        this.publishMediaMetadata(playerId, metadata);
      }
    } else {
      this.mediaMetadata.delete(playerId);
      if (this.currentPlayerId === playerId) {
        this.destroyAVSession();
      }
    }
    if (this.currentPlayerId === playerId) {
      this.publishPlaybackState(playerId);
    }
  }

  private setMediaMetadata(args: Map<string, ESObject>, result: MethodResult): void {
    const playerId = this.numberArg(args, 'playerId', 0);
    if (!this.players.has(playerId)) {
      result.error('ERIKA_ERROR', 'Unknown Erika player ' + playerId, null);
      return;
    }
    const metadata = this.parseMediaMetadata(args.get('metadata'));
    if (metadata === null) {
      result.error('INVALID_ARGUMENT', 'metadata.title is required', null);
      return;
    }
    this.mediaMetadata.set(playerId, metadata);
    result.success(null);
    if (this.currentPlayerId === playerId) {
      this.publishMediaMetadata(playerId, metadata);
    }
  }

  private setSystemMediaNavigation(
    args: Map<string, ESObject>,
    result: MethodResult,
  ): void {
    const playerId = this.numberArg(args, 'playerId', 0);
    if (!this.players.has(playerId)) {
      result.error('ERIKA_ERROR', 'Unknown Erika player ' + playerId, null);
      return;
    }
    this.mediaNavigation.set(playerId, {
      previousEnabled: args.get('previousEnabled') === true,
      nextEnabled: args.get('nextEnabled') === true,
    });
    result.success(null);
    const metadata = this.mediaMetadata.get(playerId);
    if (metadata !== undefined && this.currentPlayerId === playerId) {
      this.publishMediaMetadata(playerId, metadata);
    }
  }

  private createTexture(args: Map<string, ESObject>, result: MethodResult): void {
    const registry = this.binding?.getTextureRegistry();
    if (!registry) {
      result.error('NO_TEXTURE_REGISTRY', 'TextureRegistry is unavailable', null);
      return;
    }
    const width = Math.max(1, Math.trunc(this.numberArg(args, 'width', 1)));
    const height = Math.max(1, Math.trunc(this.numberArg(args, 'height', 1)));
    const scale = Math.max(0.1, this.numberArg(args, 'scale', 1.0));
    const textureId = registry.getTextureId();
    const entry = registry.registerTexture(textureId);
    registry.setTextureBufferSize(textureId, width, height);
    this.textures.set(textureId, {
      entry: entry,
      surfaceId: entry.getSurfaceId(),
      width: width,
      height: height,
      scale: scale,
      playerId: 0,
    });
    result.success(textureId);
  }

  private resizeTexture(args: Map<string, ESObject>, result: MethodResult): void {
    const textureId = this.numberArg(args, 'textureId', -1);
    const texture = this.textures.get(textureId);
    if (!texture) {
      result.error('ERIKA_ERROR', 'Unknown Erika texture ' + textureId, null);
      return;
    }
    texture.width = Math.max(1, Math.trunc(this.numberArg(args, 'width', texture.width)));
    texture.height = Math.max(1, Math.trunc(this.numberArg(args, 'height', texture.height)));
    texture.scale = Math.max(0.1, this.numberArg(args, 'scale', texture.scale));
    this.binding?.getTextureRegistry()?.setTextureBufferSize(
      textureId,
      texture.width,
      texture.height,
    );
    if (texture.playerId > 0) {
      const status = erikaNative.nativeResizeSurface(
        texture.playerId,
        texture.width,
        texture.height,
        texture.scale,
      ) as number;
      if (!this.completeStatus(status, result, 'resize OpenHarmony surface')) {
        return;
      }
    }
    result.success(null);
  }

  private releaseTexture(args: Map<string, ESObject>, result: MethodResult): void {
    const textureId = this.numberArg(args, 'textureId', -1);
    const texture = this.textures.get(textureId);
    if (texture) {
      if (texture.playerId > 0) {
        erikaNative.nativeDetachSurface(texture.playerId);
      }
      this.binding?.getTextureRegistry()?.unregisterTexture(textureId);
      this.textures.delete(textureId);
    }
    result.success(null);
  }

  private attachView(args: Map<string, ESObject>, result: MethodResult): void {
    const playerId = this.numberArg(args, 'playerId', 0);
    const textureId = this.numberArg(args, 'viewId', -1);
    const texture = this.textures.get(textureId);
    if (!this.players.has(playerId) || !texture) {
      result.error('ERIKA_ERROR', 'Unknown Erika player or texture', null);
      return;
    }
    if (texture.playerId > 0 && texture.playerId !== playerId) {
      erikaNative.nativeDetachSurface(texture.playerId);
    }
    const status = erikaNative.nativeAttachSurface(
      playerId,
      texture.surfaceId,
      texture.width,
      texture.height,
      texture.scale,
    ) as number;
    if (!this.completeStatus(status, result, 'attach OpenHarmony surface')) {
      return;
    }
    texture.playerId = playerId;
    result.success(null);
    this.drainEvents(playerId);
  }

  private detachView(args: Map<string, ESObject>, result: MethodResult): void {
    const playerId = this.numberArg(args, 'playerId', 0);
    const textureId = this.numberArg(args, 'viewId', -1);
    const texture = this.textures.get(textureId);
    if (!texture || texture.playerId !== playerId) {
      result.success(null);
      return;
    }
    const status = erikaNative.nativeDetachSurface(playerId) as number;
    texture.playerId = 0;
    if (!this.completeStatus(status, result, 'detach OpenHarmony surface')) {
      return;
    }
    result.success(null);
    this.drainEvents(playerId);
  }

  private captureFrame(args: Map<string, ESObject>, result: MethodResult): void {
    const playerId = this.numberArg(args, 'playerId', 0);
    if (!this.players.has(playerId)) {
      result.error('ERIKA_ERROR', 'Unknown Erika player ' + playerId, null);
      return;
    }

    let fallbackWidth = 0;
    let fallbackHeight = 0;
    this.textures.forEach((texture: ErikaTexture): void => {
      if (texture.playerId === playerId) {
        fallbackWidth = texture.width;
        fallbackHeight = texture.height;
      }
    });
    const width = Math.trunc(this.numberArg(args, 'width', fallbackWidth));
    const height = Math.trunc(this.numberArg(args, 'height', fallbackHeight));
    if (width <= 0 || height <= 0) {
      result.error(
        'ERIKA_ERROR',
        'Screenshot width and height are required before an OpenHarmony surface is attached',
        null,
      );
      return;
    }

    const bytes = erikaNative.nativeCaptureFrame(
      playerId,
      width,
      height,
    ) as Uint8Array | null;
    result.success(bytes);
  }

  private invokePlayer(
    method: string,
    args: Map<string, ESObject>,
    result: MethodResult,
  ): void {
    if (!this.invokePlayerNative(method, args, result)) {
      return;
    }
    const playerId = this.numberArg(args, 'playerId', 0);
    if (method === 'play') {
      this.currentPlayerId = playerId;
      const metadata = this.mediaMetadata.get(playerId);
      if (metadata !== undefined) {
        this.publishMediaMetadata(playerId, metadata);
      }
      this.publishPlaybackState(playerId);
    } else if (method === 'setPlaybackRate') {
      const state = this.mediaStates.get(playerId);
      if (state !== undefined) {
        state.playbackRate = this.numberArg(args, 'rate', 1.0);
      }
      this.publishPlaybackState(playerId);
    }
  }

  private invokePlayerNative(
    method: string,
    args: Map<string, ESObject>,
    result: MethodResult,
  ): boolean {
    const playerId = this.numberArg(args, 'playerId', 0);
    if (!this.players.has(playerId)) {
      result.error('ERIKA_ERROR', 'Unknown Erika player ' + playerId, null);
      return false;
    }
    const argumentsJson = JSON.stringify(this.mapToObject(args));
    const raw = erikaNative.nativeInvoke(playerId, method, argumentsJson) as string;
    const response = JSON.parse(raw) as NativeResponse;
    if (!response.ok) {
      result.error(
        'ERIKA_ERROR',
        response.error ?? ('Erika native method failed with status ' + response.status),
        response,
      );
      return false;
    }
    result.success(response.value ?? null);
    this.drainEvents(playerId);
    return true;
  }

  private parseMediaMetadata(value: ESObject): ErikaMediaMetadata | null {
    if (!(value instanceof Map)) {
      return null;
    }
    const metadata: Map<string, ESObject> = value as Map<string, ESObject>;
    const titleValue: ESObject = metadata.get('title');
    if (typeof titleValue !== 'string' || titleValue.length === 0) {
      return null;
    }
    const parsed: ErikaMediaMetadata = { title: titleValue };
    const artist: ESObject = metadata.get('artist');
    const album: ESObject = metadata.get('album');
    const artwork: ESObject = metadata.get('artwork');
    if (typeof artist === 'string') {
      parsed.artist = artist;
    }
    if (typeof album === 'string') {
      parsed.album = album;
    }
    if (artwork instanceof Uint8Array) {
      parsed.artwork = artwork;
    }
    return parsed;
  }

  private async ensureAVSession(): Promise<avSession.AVSession | null> {
    if (this.currentSession !== null) {
      return this.currentSession;
    }
    if (this.sessionPromise !== null) {
      return this.sessionPromise;
    }
    const context = this.ability?.context as common.UIAbilityContext | undefined;
    if (context === undefined) {
      return null;
    }
    const generation = this.sessionGeneration;
    const promise = this.createAVSession(context, generation);
    this.sessionPromise = promise;
    const session = await promise;
    if (this.sessionPromise === promise) {
      this.sessionPromise = null;
    }
    return session;
  }

  private async createAVSession(
    context: common.UIAbilityContext,
    generation: number,
  ): Promise<avSession.AVSession | null> {
    let session: avSession.AVSession | null = null;
    try {
      session = await avSession.createAVSession(context, 'ErikaVideoPlayer', 'video');
      if (generation !== this.sessionGeneration || this.ability?.context !== context) {
        await session.destroy().catch((): void => {});
        return null;
      }
      this.registerAVSessionCommands(session);
      await session.activate();
      if (generation !== this.sessionGeneration || this.ability?.context !== context) {
        await session.destroy().catch((): void => {});
        return null;
      }
      this.currentSession = session;
      return session;
    } catch (_) {
      await session?.destroy().catch((): void => {});
      return null;
    }
  }

  private registerAVSessionCommands(session: avSession.AVSession): void {
    session.on('play', (): void => this.invokeFromAVSession('play'));
    session.on('pause', (): void => this.invokeFromAVSession('pause'));
    session.on('stop', (): void => this.invokeFromAVSession('stop'));
    session.on('seek', (time: number): void => {
      this.invokeFromAVSession('seek', new Map<string, ESObject>([
        ['positionMicros', time * 1000],
      ]));
    });
    session.on('playPrevious', (): void => this.emitSystemMediaNavigation('previous'));
    session.on('playNext', (): void => this.emitSystemMediaNavigation('next'));
  }

  private emitSystemMediaNavigation(navigation: string): void {
    const playerId = this.currentPlayerId;
    const capabilities = this.mediaNavigation.get(playerId);
    const enabled = navigation === 'previous'
      ? capabilities?.previousEnabled === true
      : capabilities?.nextEnabled === true;
    if (!this.players.has(playerId) || !enabled) {
      return;
    }
    this.eventSink?.success({
      playerId: playerId,
      kind: SYSTEM_MEDIA_NAVIGATION_EVENT_KIND,
      navigation: navigation,
    });
  }

  private invokeFromAVSession(method: string, extra?: Map<string, ESObject>): void {
    const playerId = this.currentPlayerId;
    if (!this.players.has(playerId)) {
      return;
    }
    const args: Map<string, ESObject> =
      extra ?? new Map<string, ESObject>();
    args.set('playerId', playerId);
    const raw = erikaNative.nativeInvoke(
      playerId,
      method,
      JSON.stringify(this.mapToObject(args)),
    ) as string;
    const response = JSON.parse(raw) as NativeResponse;
    if (response.ok) {
      this.drainEvents(playerId);
    }
  }

  private async publishMediaMetadata(
    playerId: number,
    metadata: ErikaMediaMetadata,
  ): Promise<void> {
    const session = await this.ensureAVSession();
    if (session === null || this.currentPlayerId !== playerId ||
      this.mediaMetadata.get(playerId) !== metadata) {
      return;
    }
    const avMetadata: avSession.AVMetadata = {
      assetId: 'erika-' + playerId,
      title: metadata.title,
    };
    const capabilities = this.mediaNavigation.get(playerId);
    if (capabilities?.previousEnabled === true) {
      avMetadata.previousAssetId = 'erika-previous-' + playerId;
    }
    if (capabilities?.nextEnabled === true) {
      avMetadata.nextAssetId = 'erika-next-' + playerId;
    }
    if (metadata.artist !== undefined) {
      avMetadata.artist = metadata.artist;
    }
    if (metadata.album !== undefined) {
      avMetadata.album = metadata.album;
    }
    let mediaImage: image.PixelMap | null = null;
    if (metadata.artwork !== undefined) {
      let source: image.ImageSource | null = null;
      try {
        const bytes = metadata.artwork;
        const artwork = new Uint8Array(bytes.byteLength);
        artwork.set(bytes);
        source = image.createImageSource(artwork.buffer as ArrayBuffer);
        mediaImage = await source.createPixelMap();
        avMetadata.mediaImage = mediaImage;
      } catch (_) {
      } finally {
        await source?.release().catch((): void => {});
      }
    }
    const state = this.mediaStates.get(playerId);
    if (state !== undefined && state.durationMicros > 0) {
      avMetadata.duration = state.durationMicros / 1000.0;
    }
    if (this.currentPlayerId !== playerId || this.mediaMetadata.get(playerId) !== metadata) {
      await mediaImage?.release().catch((): void => {});
      return;
    }
    await session.setAVMetadata(avMetadata).catch((): void => {});
    await mediaImage?.release().catch((): void => {});
  }

  private async publishPlaybackState(playerId: number): Promise<void> {
    const mediaState = this.mediaStates.get(playerId);
    if (mediaState === undefined || this.currentPlayerId !== playerId) {
      return;
    }
    const session = await this.ensureAVSession();
    if (session === null || this.currentPlayerId !== playerId) {
      return;
    }
    await session.activate().catch((): void => {});
    await session.setAVPlaybackState({
      state: this.avPlaybackState(mediaState.playbackState),
      speed: mediaState.playbackState === PLAYING_STATE ? mediaState.playbackRate : 0,
      position: {
        elapsedTime: mediaState.positionMicros / 1000.0,
        updateTime: Date.now(),
      },
      duration: mediaState.durationMicros / 1000.0,
    }).catch((): void => {});
    if (mediaState.playbackState === CLOSED_STATE || mediaState.playbackState === ERROR_STATE) {
      this.deactivateAVSession();
    }
  }

  private avPlaybackState(state: number): avSession.PlaybackState {
    if (state === PLAYING_STATE) {
      return avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    }
    if (state === PAUSED_STATE) {
      return avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    }
    if (state === STOPPED_STATE) {
      return avSession.PlaybackState.PLAYBACK_STATE_STOP;
    }
    if (state === CLOSED_STATE) {
      return avSession.PlaybackState.PLAYBACK_STATE_RELEASED;
    }
    if (state === ERROR_STATE) {
      return avSession.PlaybackState.PLAYBACK_STATE_ERROR;
    }
    return avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
  }

  private deactivateAVSession(): void {
    this.sessionGeneration += 1;
    this.sessionPromise = null;
    this.currentSession?.deactivate().catch((): void => {});
  }

  private destroyAVSession(): void {
    const session = this.currentSession;
    this.sessionGeneration += 1;
    this.currentSession = null;
    this.sessionPromise = null;
    session?.destroy().catch((): void => {});
  }

  private registerSubtitleMemoryFont(
    args: Map<string, ESObject>,
    result: MethodResult,
  ): void {
    const playerId = this.numberArg(args, 'playerId', 0);
    if (!this.players.has(playerId)) {
      result.error('ERIKA_ERROR', 'Unknown Erika player ' + playerId, null);
      return;
    }
    const data = args.get('data') as Uint8Array;
    const response = erikaNative.nativeRegisterSubtitleMemoryFont(
      playerId,
      data,
    ) as Array<number>;
    const status = response[0] ?? 1;
    if (!this.completeStatus(status, result, 'register subtitle memory font')) {
      return;
    }
    result.success(response[1] ?? 0);
  }

  private startFrameLoop(): void {
    if (this.frameTimer >= 0) {
      return;
    }
    this.frameTimer = setInterval((): void => {
      const frameTimeSeconds = Date.now() / 1000.0;
      this.players.forEach((playerId: number): void => {
        erikaNative.nativeRenderTick(playerId, frameTimeSeconds);
        this.drainEvents(playerId);
      });
    }, FRAME_INTERVAL_MS);
  }

  private stopFrameLoop(): void {
    if (this.frameTimer >= 0) {
      clearInterval(this.frameTimer);
      this.frameTimer = -1;
    }
  }

  private drainAllEvents(): void {
    this.players.forEach((playerId: number): void => this.drainEvents(playerId));
  }

  private drainEvents(playerId: number): void {
    const sink = this.eventSink;
    if (!sink) {
      return;
    }
    for (let index = 0; index < 64; index += 1) {
      const raw = erikaNative.nativePollEvent(playerId) as string | null;
      if (raw === null) {
        return;
      }
      const response = JSON.parse(raw) as NativeResponse;
      if (!response.ok || response.value === undefined) {
        return;
      }
      const event: ESObject = response.value;
      event.playerId = playerId;
      this.observeMediaEvent(playerId, event);
      sink.success(event);
    }
  }

  private observeMediaEvent(playerId: number, event: ESObject): void {
    const mediaState = this.mediaStates.get(playerId);
    if (mediaState === undefined) {
      return;
    }
    const kind = typeof event.kind === 'number' ? event.kind as number : 0;
    if (kind === STATE_CHANGED_EVENT_KIND) {
      mediaState.playbackState = typeof event.state === 'number'
        ? event.state as number
        : mediaState.playbackState;
    }
    if (kind === POSITION_CHANGED_EVENT_KIND && typeof event.positionMicros === 'number') {
      mediaState.positionMicros = Math.max(0, event.positionMicros as number);
    }
    if ((kind === DURATION_CHANGED_EVENT_KIND || kind === STATE_CHANGED_EVENT_KIND) &&
      typeof event.durationMicros === 'number') {
      mediaState.durationMicros = Math.max(0, event.durationMicros as number);
    }
    if (this.currentPlayerId !== playerId) {
      return;
    }
    if (kind === DURATION_CHANGED_EVENT_KIND) {
      const metadata = this.mediaMetadata.get(playerId);
      if (metadata !== undefined) {
        this.publishMediaMetadata(playerId, metadata);
      }
    }
    if (kind === STATE_CHANGED_EVENT_KIND || kind === DURATION_CHANGED_EVENT_KIND ||
      kind === POSITION_CHANGED_EVENT_KIND) {
      this.publishPlaybackState(playerId);
    }
  }

  private completeStatus(status: number, result: MethodResult, operation: string): boolean {
    if (status === 0) {
      return true;
    }
    const nativeError = erikaNative.nativeLastError() as string;
    result.error(
      'ERIKA_ERROR',
      operation + ' failed' + (nativeError.length > 0 ? ': ' + nativeError : ''),
      status,
    );
    return false;
  }

  private numberArg(
    args: Map<string, ESObject>,
    name: string,
    fallback: number,
  ): number {
    const value: ESObject = args.get(name);
    return typeof value === 'number' ? value as number : fallback;
  }

  private mapToObject(args: Map<string, ESObject>): ESObject {
    const object: ESObject = {};
    args.forEach((value: ESObject, key: string): void => {
      object[key] = this.jsonValue(value);
    });
    return object;
  }

  private jsonValue(value: ESObject): ESObject {
    if (value instanceof Map) {
      return this.mapToObject(value as Map<string, ESObject>);
    }
    if (Array.isArray(value)) {
      return (value as Array<ESObject>).map(
        (child: ESObject): ESObject => this.jsonValue(child),
      );
    }
    return value;
  }

  private isNativePlayerMethod(method: string): boolean {
    return [
      'open', 'play', 'pause', 'stop', 'close', 'seek',
      'setPlaybackRate', 'setVolume', 'setUpscaler', 'setSubtitleScale',
      'selectSubtitleMemoryFonts', 'clearSubtitleMemoryFonts',
      'getSubtitleMemoryFontStatus',
      'getUpscalerStatus', 'getOutputStatus', 'getPresenterStats',
      'getResourceStatus',
      'addExternalSubtitle', 'removeSubtitleTrack',
      'loadDanmakuFile', 'loadDanmakuJson',
      'addDanmakuTrackFile', 'addDanmakuTrackJson',
      'removeDanmakuTrack', 'setDanmakuTrackEnabled',
      'setDanmakuTrackOffset', 'setDanmakuGlobalOffset',
      'danmakuTracks', 'clearDanmaku', 'setDanmakuEnabled',
      'setDanmakuConfig', 'selectAudioTrack', 'selectSubtitleTrack', 'tracks',
      'getDiagnosticsSnapshot', 'getLogs', 'invokeJson',
    ].includes(method);
  }
}
