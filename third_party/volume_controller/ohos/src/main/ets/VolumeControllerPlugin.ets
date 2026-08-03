import {
  EventChannel,
  EventSink,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  StandardMethodCodec
} from '@ohos/flutter_ohos';
import { audio } from '@kit.AudioKit';

const METHOD_CHANNEL_NAME: string = 'com.kurenai7968.volume_controller.method';
const EVENT_CHANNEL_NAME: string =
  'com.kurenai7968.volume_controller.volume_listener_event';
const MEDIA_VOLUME_TYPE: audio.AudioVolumeType = audio.AudioVolumeType.MEDIA;
const DEFAULT_VOLUME_GROUP_ID: number = audio.DEFAULT_VOLUME_GROUP_ID;

export default class VolumeControllerPlugin
  implements FlutterPlugin, MethodCallHandler {
  private methodChannel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private eventSink: EventSink | null = null;
  private volumeManager: audio.AudioVolumeManager | null = null;
  private volumeGroupManager: audio.AudioVolumeGroupManager | null = null;
  private lastNonZeroVolume: number = 0.5;
  private readonly onVolumeChange: (eventData: audio.VolumeEvent) => void =
    (_eventData: audio.VolumeEvent): void => {
      this.emitCurrentVolume();
    };

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    const messenger = binding.getBinaryMessenger();
    this.methodChannel =
      new MethodChannel(messenger, METHOD_CHANNEL_NAME, StandardMethodCodec.INSTANCE);
    this.methodChannel.setMethodCallHandler(this);
    this.eventChannel =
      new EventChannel(messenger, EVENT_CHANNEL_NAME, StandardMethodCodec.INSTANCE);
    this.eventChannel.setStreamHandler({
      onListen: (args: ESObject, sink: EventSink): void => {
        this.handleEventListen(args, sink);
      },
      onCancel: (_args: ESObject): void => {
        this.handleEventCancel();
      }
    });
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.unregisterVolumeListener();
    this.eventSink = null;
    if (this.methodChannel !== null) {
      this.methodChannel.setMethodCallHandler(null);
      this.methodChannel = null;
    }
    if (this.eventChannel !== null) {
      this.eventChannel.setStreamHandler(null);
      this.eventChannel = null;
    }
  }

  getUniqueClassName(): string {
    return 'VolumeControllerPlugin';
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'getVolume') {
      this.getVolume()
        .then((volume: number): void => result.success(volume))
        .catch((error: Error): void =>
          result.error('getVolume_failed', error.message, null));
      return;
    }

    if (call.method === 'setVolume') {
      const volume: number | null = this.getNumberArg(call.args, 'volume');
      if (volume === null) {
        result.error('setVolume_failed', 'volume is required', null);
        return;
      }
      this.setVolume(volume)
        .then((): void => result.success(null))
        .catch((error: Error): void =>
          result.error('setVolume_failed', error.message, null));
      return;
    }

    if (call.method === 'isMuted') {
      this.isMuted()
        .then((muted: boolean): void => result.success(muted))
        .catch((error: Error): void =>
          result.error('isMuted_failed', error.message, null));
      return;
    }

    if (call.method === 'setMute') {
      const muted: boolean | null = this.getBooleanArg(call.args, 'isMute');
      if (muted === null) {
        result.error('setMute_failed', 'isMute is required', null);
        return;
      }
      this.setMuted(muted)
        .then((): void => result.success(null))
        .catch((error: Error): void =>
          result.error('setMute_failed', error.message, null));
      return;
    }

    result.notImplemented();
  }

  private handleEventListen(args: ESObject, sink: EventSink): void {
    this.eventSink = sink;
    this.ensureVolumeManager()
      .then((manager: audio.AudioVolumeManager): void => {
        this.registerVolumeListener(manager);
        const fetchInitial: boolean =
          this.getBooleanArg(args, 'fetchInitialVolume') ?? true;
        if (fetchInitial) {
          this.emitCurrentVolume();
        }
      })
      .catch((error: Error): void => {
        this.eventSink?.error('event_listen_failed', error.message, null);
      });
  }

  private handleEventCancel(): void {
    this.unregisterVolumeListener();
    this.eventSink = null;
  }

  private registerVolumeListener(manager: audio.AudioVolumeManager): void {
    try {
      manager.off('volumeChange', this.onVolumeChange);
    } catch (_error) {
      // Ignore a listener that was not registered yet.
    }
    manager.on('volumeChange', this.onVolumeChange);
  }

  private unregisterVolumeListener(): void {
    if (this.volumeManager === null) {
      return;
    }
    try {
      this.volumeManager.off('volumeChange', this.onVolumeChange);
    } catch (_error) {
      // Ignore cleanup after the audio service has already stopped.
    }
  }

  private async ensureVolumeManager(): Promise<audio.AudioVolumeManager> {
    if (this.volumeManager === null) {
      this.volumeManager = audio.getAudioManager().getVolumeManager();
    }
    return this.volumeManager;
  }

  private async ensureVolumeGroupManager(): Promise<audio.AudioVolumeGroupManager> {
    if (this.volumeGroupManager === null) {
      this.volumeGroupManager = await audio
        .getAudioManager()
        .getVolumeManager()
        .getVolumeGroupManager(DEFAULT_VOLUME_GROUP_ID);
    }
    return this.volumeGroupManager;
  }

  private async emitCurrentVolume(): Promise<void> {
    if (this.eventSink === null) {
      return;
    }
    try {
      const currentVolume: number = await this.getVolume();
      this.eventSink?.success(currentVolume);
    } catch (_error) {
      // Transient audio service errors should not terminate the event stream.
    }
  }

  private async getVolume(): Promise<number> {
    const manager: audio.AudioVolumeGroupManager =
      await this.ensureVolumeGroupManager();
    const current: number = await manager.getVolume(MEDIA_VOLUME_TYPE);
    const max: number = await manager.getMaxVolume(MEDIA_VOLUME_TYPE);
    if (max <= 0) {
      return 0;
    }
    return this.clampToUnit(current / max);
  }

  private async setVolume(volume: number): Promise<void> {
    const manager: audio.AudioVolumeGroupManager =
      await this.ensureVolumeGroupManager();
    const max: number = await manager.getMaxVolume(MEDIA_VOLUME_TYPE);
    if (max <= 0) {
      return;
    }
    const normalized: number = this.clampToUnit(volume);
    const target: number = Math.round(normalized * max);
    await audio.getAudioManager().setVolume(MEDIA_VOLUME_TYPE, target);
    if (normalized > 0) {
      this.lastNonZeroVolume = normalized;
    }
  }

  private async isMuted(): Promise<boolean> {
    const manager: audio.AudioVolumeGroupManager =
      await this.ensureVolumeGroupManager();
    return await manager.getVolume(MEDIA_VOLUME_TYPE) <= 0;
  }

  private async setMuted(muted: boolean): Promise<void> {
    if (muted) {
      const current: number = await this.getVolume();
      if (current > 0) {
        this.lastNonZeroVolume = current;
      }
      await this.setVolume(0);
      return;
    }
    await this.setVolume(
      this.lastNonZeroVolume > 0 ? this.lastNonZeroVolume : 0.5);
  }

  private getNumberArg(args: ESObject, key: string): number | null {
    const value: Object | null = this.getArgValue(args, key);
    return value === null ? null : value as number;
  }

  private getBooleanArg(args: ESObject, key: string): boolean | null {
    const value: Object | null = this.getArgValue(args, key);
    return value === null ? null : value as boolean;
  }

  private getArgValue(args: ESObject, key: string): Object | null {
    if (args === undefined || args === null) {
      return null;
    }
    const object: Object = args as Object;
    if (object instanceof Map) {
      const value: Object | undefined =
        (object as Map<string, Object>).get(key);
      return value === undefined || value === null ? null : value;
    }
    const value: ESObject = args[key];
    return value === undefined || value === null ? null : value as Object;
  }

  private clampToUnit(value: number): number {
    return Math.max(0, Math.min(1, value));
  }
}
