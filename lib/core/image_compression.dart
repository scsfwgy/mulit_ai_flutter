import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Sampling adapted from Luban 1.1.8 (Curzibn), Apache-2.0.
/// Copyright 2016 Zheng Zibin. See assets/licenses/luban.txt.
/// https://github.com/Curzibn/Luban/blob/1.1.8/library/src/main/java/top/zibin/luban/Engine.java
/// Changes: bounded decoded pixels, quality 85, lossless PNG/animation retention,
/// and original-byte fallback when recompression increases file size.
(int, int) chatImageTargetSize(int width, int height) {
  final longSide = math.max(width + width % 2, height + height % 2);
  final shortSide = math.min(width + width % 2, height + height % 2);
  final ratio = shortSide / longSide;
  final int sample;
  if (ratio > .5625) {
    sample = longSide < 1664
        ? 1
        : longSide < 4990
        ? 2
        : longSide < 10240
        ? 4
        : math.max(1, longSide ~/ 1280);
  } else if (ratio > .5) {
    sample = math.max(1, longSide ~/ 1280);
  } else {
    sample = math.max(1, (shortSide / 1280).ceil());
  }
  // Luban 2 also bounds long-image pixels; decode at the target size rather
  // than allocating the full-resolution bitmap before shrinking it.
  final scale = math.min(1 / sample, math.sqrt(10240000 / (width * height)));
  return (
    math.max(1, (width * scale).floor()),
    math.max(1, (height * scale).floor()),
  );
}

Future<(Uint8List, String)> compressChatImage(
  Uint8List bytes,
  String mime,
) async {
  if (bytes.length <= 100 * 1024 || mime == 'image/gif') return (bytes, mime);
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? decoded;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final (width, height) = chatImageTargetSize(
      descriptor.width,
      descriptor.height,
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: width,
      targetHeight: height,
    );
    // Do not silently flatten animated PNG/WebP to one frame.
    if (codec.frameCount > 1) return (bytes, mime);
    decoded = (await codec.getNextFrame()).image;
    final raw = await decoded.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (raw == null) return (bytes, mime);
    final result = await compute(_encodeChatImage, (
      raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      decoded.width,
      decoded.height,
      mime,
    ));
    return result.$1.length < bytes.length ? result : (bytes, mime);
  } finally {
    decoded?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

(Uint8List, String) _encodeChatImage((Uint8List, int, int, String) input) {
  final (raw, width, height, mime) = input;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: raw.buffer,
    bytesOffset: raw.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  var transparent = false;
  for (var i = 3; i < raw.length; i += 4) {
    if (raw[i] != 255) {
      transparent = true;
      break;
    }
  }
  if (transparent) return (img.encodePng(image), 'image/png');
  final jpeg = img.encodeJpg(image, quality: 85);
  if (mime == 'image/png') {
    final png = img.encodePng(image);
    // Flat-color screenshots and text usually compress well losslessly.
    if (png.length <= jpeg.length * 1.25) return (png, 'image/png');
  }
  return (jpeg, 'image/jpeg');
}
