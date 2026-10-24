import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/image_compression.dart';

void main() {
  test(
    'Luban sampling preserves long screenshots and bounds decoded pixels',
    () {
      expect(chatImageTargetSize(4032, 3024), (2016, 1512));
      expect(chatImageTargetSize(1200, 800), (1200, 800));
      expect(chatImageTargetSize(1000, 8000), (1000, 8000));
      expect(chatImageTargetSize(1, 8000), (1, 8000));
      final (w, h) = chatImageTargetSize(1280, 20000);
      expect(w * h, lessThanOrEqualTo(10240000));
      expect(w / h, closeTo(1280 / 20000, .001));
    },
  );

  test('small images and animated GIFs retain original bytes', () async {
    final small = img.encodeJpg(img.Image(width: 20, height: 10));
    final result = await compressChatImage(small, 'image/jpeg');
    expect(identical(result.$1, small), isTrue);
    final animation = img.Image(width: 30, height: 20);
    animation.addFrame(img.Image(width: 30, height: 20));
    final gif = Uint8List.fromList([
      ...img.encodeGif(animation),
      ...List.filled(110000, 0),
    ]);
    expect((await compressChatImage(gif, 'image/gif')).$1, gif);
  });

  test(
    'photo compression respects EXIF orientation and never expands a JPEG',
    () async {
      final image = img.Image(width: 1800, height: 1200);
      var random = 7;
      for (final pixel in image) {
        random = (random * 1664525 + 1013904223) & 0xffffffff;
        pixel
          ..r = random & 255
          ..g = (random >> 8) & 255
          ..b = (random >> 16) & 255;
      }
      image.exif.imageIfd.orientation = 6;
      final original = img.encodeJpg(image, quality: 95);
      final (bytes, mime) = await compressChatImage(original, 'image/jpeg');
      expect(mime, 'image/jpeg');
      expect(bytes.length, lessThan(original.length));
      final decoded = img.decodeJpg(bytes)!;
      expect((decoded.width, decoded.height), (600, 900));
      image.exif.imageIfd.orientation = 1;
      final lowQuality = img.encodeJpg(
        img.copyResize(image, width: 1200, height: 800),
        quality: 20,
      );
      expect(lowQuality.length, greaterThan(100 * 1024));
      final fallback = await compressChatImage(lowQuality, 'image/jpeg');
      expect(identical(fallback.$1, lowQuality), isTrue);
    },
  );

  test(
    'text screenshots remain lossless and transparent PNGs keep alpha',
    () async {
      final screenshot = img.Image(width: 1200, height: 900);
      img.fill(screenshot, color: img.ColorRgb8(255, 255, 255));
      for (var y = 10; y < 850; y += 35) {
        img.drawString(
          screenshot,
          'Invoice #12345  Total: 199.95 USD',
          font: img.arial24,
          x: 20,
          y: y,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
      final source = img.encodePng(screenshot, level: 0);
      final (bytes, mime) = await compressChatImage(source, 'image/png');
      expect(bytes.length, lessThan(source.length));
      expect(mime, 'image/png');
      final decoded = img.decodePng(bytes)!;
      expect(
        decoded.getBytes(order: img.ChannelOrder.rgb),
        screenshot.getBytes(),
      );

      final transparent = img.Image(width: 400, height: 400, numChannels: 4);
      img.fill(transparent, color: img.ColorRgba8(10, 90, 200, 120));
      final alpha = await compressChatImage(
        img.encodePng(transparent, level: 0),
        'image/png',
      );
      expect(alpha.$2, 'image/png');
      expect(img.decodePng(alpha.$1)!.getPixel(20, 20).a, 120);
    },
  );

  test(
    'all entry points import compressed copies and preserve source files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai-link-image-compression-',
      );
      addTearDown(() => root.delete(recursive: true));
      final image = img.Image(width: 3600, height: 2700, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(100, 150, 200, 255));
      final original = img.encodePng(image, level: 0);
      expect(original.length, greaterThan(AttachmentStore.maxFileBytes));
      final source = await File('${root.path}/photo.png')
          .writeAsBytes(original);
      final store = AttachmentStore(Directory('${root.path}/owned'));
      for (final imageOnly in [true, false]) {
        final attachment = await store.importFile(
          source.path,
          'photo.png',
          imageOnly: imageOnly,
        );
        final saved = await store.read(attachment);
        expect(saved.length, attachment.size);
        expect(saved.length, lessThan(original.length));
        expect(saved.length, lessThanOrEqualTo(AttachmentStore.maxFileBytes));
        final decoded = img.decodeImage(saved)!;
        expect((decoded.width, decoded.height), (1800, 1350));
        expect(
          attachment.fileName,
          endsWith(attachment.mimeType == 'image/png' ? '.png' : '.jpg'),
        );
      }
      expect(await source.readAsBytes(), original);
    },
  );
}
