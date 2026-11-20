import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Plain data for thumbnail encoding on a worker isolate. No player or UI state
/// may cross this boundary; native frame capture still happens at the caller.
class VideoFrameImageRequest {
  const VideoFrameImageRequest(
      {required this.bytes,
      required this.width,
      required this.height,
      this.sourceWidth = 0,
      this.sourceHeight = 0,
      this.bgra = false});
  final Uint8List bytes;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;
  final bool bgra;
}

const int thumbnailMaxHeight = 240;
const int thumbnailMaxWidth = 480;
const int _thumbnailJpegQuality = 70;

class _RawFrameSpec {
  final int width;
  final int height;
  final int? rowStride;

  const _RawFrameSpec({
    required this.width,
    required this.height,
    this.rowStride,
  });
}

bool _isPngBytes(Uint8List bytes) {
  return bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;
}

bool _isJpegBytes(Uint8List bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
}

img.Image _forceOpaqueImage(img.Image image) {
  if (!image.hasAlpha) {
    return image.convert(
      numChannels: 4,
      alpha: image.maxChannelValue,
    );
  }
  final alpha = image.maxChannelValue;
  for (final pixel in image) {
    pixel.a = alpha;
  }
  return image;
}

img.Image? decodeVideoFrameImage(VideoFrameImageRequest frame) {
  final frameBytes = frame.bytes;
  final isPng = _isPngBytes(frameBytes);
  final isJpeg = _isJpegBytes(frameBytes);

  img.Image? decoded;
  if (isPng || isJpeg) {
    try {
      decoded = img.decodeImage(frameBytes);
    } catch (_) {}
    if (decoded != null) {
      return _forceOpaqueImage(decoded);
    }
  } else {
    try {
      decoded = img.decodeImage(frameBytes);
    } catch (_) {}
    if (decoded != null) {
      return _forceOpaqueImage(decoded);
    }
  }

  final rawSpec = _matchRawFrameSpec(frame);
  if (rawSpec == null) {
    return null;
  }

  final expectedLength = rawSpec.width * rawSpec.height * 4;
  if (frameBytes.length < expectedLength ||
      (frameBytes.length != expectedLength && rawSpec.rowStride == null)) {
    return null;
  }

  final channelOrder =
      frame.bgra ? img.ChannelOrder.bgra : img.ChannelOrder.rgba;
  final rawCopy = Uint8List.fromList(frameBytes);

  final image = img.Image.fromBytes(
    width: rawSpec.width,
    height: rawSpec.height,
    bytes: rawCopy.buffer,
    numChannels: 4,
    rowStride: rawSpec.rowStride,
    order: channelOrder,
  );

  return _forceOpaqueImage(image);
}

img.Image _resizeThumbnailImage(img.Image image) {
  if (image.width <= thumbnailMaxWidth && image.height <= thumbnailMaxHeight) {
    return image;
  }

  final widthRatio = image.width / thumbnailMaxWidth;
  final heightRatio = image.height / thumbnailMaxHeight;
  if (widthRatio >= heightRatio) {
    return img.copyResize(image, width: thumbnailMaxWidth);
  }
  return img.copyResize(image, height: thumbnailMaxHeight);
}

bool _isLikelyBlankThumbnailFrame(img.Image image) {
  const sampleLimit = 4096;
  const brightThreshold = 18;
  final totalPixels = image.width * image.height;
  if (totalPixels <= 0) return true;

  final sampleStep = (totalPixels / sampleLimit).ceil().clamp(1, totalPixels);
  var sampled = 0;
  var brightPixels = 0;
  for (var index = 0; index < totalPixels; index += sampleStep) {
    final pixel = image.getPixel(index % image.width, index ~/ image.width);
    sampled++;
    final maxChannel =
        math.max(pixel.r.toInt(), math.max(pixel.g.toInt(), pixel.b.toInt()));
    if (maxChannel > brightThreshold) brightPixels++;
  }

  if (sampled == 0) return true;
  return brightPixels / sampled < 0.002;
}

Uint8List? encodeVideoThumbnail(VideoFrameImageRequest frame) {
  final decoded = decodeVideoFrameImage(frame);
  if (decoded == null) {
    return null;
  }
  if (_isLikelyBlankThumbnailFrame(decoded)) {
    return null;
  }
  final resized = _resizeThumbnailImage(decoded);
  return Uint8List.fromList(
    img.encodeJpg(resized, quality: _thumbnailJpegQuality),
  );
}

_RawFrameSpec? _matchRawFrameSpec(VideoFrameImageRequest frame) {
  final byteLength = frame.bytes.length;
  final candidates = <_RawFrameSpec>[];

  void addCandidate(int width, int height) {
    if (width > 0 && height > 0) {
      candidates.add(_RawFrameSpec(width: width, height: height));
    }
  }

  addCandidate(frame.width, frame.height);

  addCandidate(frame.sourceWidth, frame.sourceHeight);

  for (final candidate in candidates) {
    final expected = candidate.width * candidate.height * 4;
    if (byteLength == expected) {
      return candidate;
    }
  }

  for (final candidate in candidates) {
    if (byteLength % candidate.height != 0) {
      continue;
    }
    final stride = byteLength ~/ candidate.height;
    if (stride >= candidate.width * 4) {
      return _RawFrameSpec(
        width: candidate.width,
        height: candidate.height,
        rowStride: stride,
      );
    }
  }

  return null;
}
