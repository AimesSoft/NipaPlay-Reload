/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0.
 */

import BasicMessageChannel, {
  Reply,
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/MessageCodec';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import { ByteBuffer } from '@ohos/flutter_ohos/src/main/ets/util/ByteBuffer';

export class ToggleMessage {
  private enable: boolean;

  constructor(enable: boolean) {
    this.enable = enable;
  }

  getEnable(): boolean {
    return this.enable;
  }

  toList(): Object[] {
    return [this.enable];
  }

  static fromList(message: Object): ToggleMessage {
    const list = message as Array<Object>;
    return new ToggleMessage(list[0] as boolean);
  }
}

export class IsEnabledMessage {
  private enabled: boolean;

  constructor(enabled: boolean) {
    this.enabled = enabled;
  }

  toList(): Object[] {
    return [this.enabled];
  }

  static fromList(message: Object): IsEnabledMessage {
    const list = message as Array<Object>;
    return new IsEnabledMessage(list[0] as boolean);
  }
}

class WakelockApiCodec extends StandardMessageCodec {
  static readonly INSTANCE: WakelockApiCodec = new WakelockApiCodec();

  private getByte(value: number): number {
    const bytes = new Uint8Array(1);
    bytes[0] = value;
    return bytes[0] as number;
  }

  readValueOfType(type: number, buffer: ByteBuffer): ESObject {
    switch (type) {
      case this.getByte(129):
        return ToggleMessage.fromList(super.readValue(buffer));
      case this.getByte(130):
        return IsEnabledMessage.fromList(super.readValue(buffer));
      default:
        return super.readValueOfType(type, buffer);
    }
  }

  writeValue(stream: ByteBuffer, value: ESObject): ESObject {
    if (value instanceof ToggleMessage) {
      stream.writeInt8(this.getByte(129));
      return this.writeValue(stream, value.toList());
    }
    if (value instanceof IsEnabledMessage) {
      stream.writeInt8(this.getByte(130));
      return this.writeValue(stream, value.toList());
    }
    return super.writeValue(stream, value);
  }
}

export abstract class WakelockApi {
  abstract toggle(message: ToggleMessage): Promise<void>;

  abstract isEnabled(): Promise<IsEnabledMessage>;

  static getCodec(): MessageCodec<Object> {
    return WakelockApiCodec.INSTANCE;
  }

  static setup(
    binaryMessenger: BinaryMessenger,
    api: WakelockApi | null,
  ): void {
    const toggleChannel = new BasicMessageChannel<Object>(
      binaryMessenger,
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      WakelockApi.getCodec(),
    );
    if (api === null) {
      toggleChannel.setMessageHandler(null);
    } else {
      toggleChannel.setMessageHandler({
        async onMessage(message: Object, reply: Reply<Object>) {
          const args = message as Array<Object>;
          try {
            await api.toggle(args[0] as ToggleMessage);
            reply.reply([null]);
          } catch (error) {
            reply.reply(WakelockApi.wrapError(error as Error));
          }
        },
      });
    }

    const enabledChannel = new BasicMessageChannel<Object>(
      binaryMessenger,
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled',
      WakelockApi.getCodec(),
    );
    if (api === null) {
      enabledChannel.setMessageHandler(null);
    } else {
      enabledChannel.setMessageHandler({
        async onMessage(_message: Object, reply: Reply<Object>) {
          try {
            reply.reply([await api.isEnabled()]);
          } catch (error) {
            reply.reply(WakelockApi.wrapError(error as Error));
          }
        },
      });
    }
  }

  private static wrapError(error: Error): Object[] {
    return [
      error.name,
      error.message,
      `Cause: ${error.message}, Stacktrace: ${error.stack}`,
    ];
  }
}
