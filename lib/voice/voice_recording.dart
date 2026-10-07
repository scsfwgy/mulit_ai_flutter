import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mulit_ai_flutter/voice/voice_client.dart';

/// Captures actual microphone frames instead of relying on recorder file flushes.
class PcmVoiceRecording {
  PcmVoiceRecording(Stream<Uint8List> stream) {
    _subscription = stream.listen(
      (chunk) {
        if (_failed) return;
        if (_pcm.length + chunk.length > 2 * 1024 * 1024) {
          _failed = true;
          _pcm.clear();
          return;
        }
        _pcm.add(chunk);
      },
      onError: (Object _) {
        _failed = true;
      },
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
    );
  }

  final _pcm = BytesBuilder();
  final _done = Completer<void>();
  late final StreamSubscription<Uint8List> _subscription;
  bool _failed = false;

  /// Call after recorder.stop(); the stream's final frames must arrive first.
  Future<Uint8List> finish() async {
    try {
      await _done.future.timeout(const Duration(seconds: 3));
      if (_failed) throw const VoiceException('录音采集失败，请重试');
      return pcm16VoiceWav(_pcm.takeBytes());
    } on TimeoutException {
      throw const VoiceException('录音未完整结束，请重试');
    } finally {
      await discard();
    }
  }

  Future<void> discard() async {
    _failed = true;
    await _subscription.cancel();
    _pcm.clear();
    if (!_done.isCompleted) _done.complete();
  }
}

Uint8List pcm16VoiceWav(Uint8List pcm) {
  if (pcm.isEmpty) {
    throw const VoiceException('没有录到音频，请检查麦克风后重试');
  }
  if (pcm.length.isOdd) throw const VoiceException('录音数据不完整，请重试');
  final wav = Uint8List(44 + pcm.length);
  final header = ByteData.sublistView(wav);
  void tag(int offset, String text) =>
      wav.setRange(offset, offset + 4, ascii.encode(text));
  tag(0, 'RIFF');
  header.setUint32(4, wav.length - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 16000, Endian.little);
  header.setUint32(28, 32000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  wav.setRange(44, wav.length, pcm);
  return wav;
}
