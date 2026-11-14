import 'dart:async';
import 'dart:typed_data';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/voice/voice_audio.dart';

export 'package:mulit_ai_flutter/voice/voice_audio.dart' show pcm16VoiceWav;

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
      if (_failed) {
        throw VoiceException(T('i18n.audio_capture_failed_try_again'));
      }
      return pcm16VoiceWav(_pcm.takeBytes());
    } on TimeoutException {
      throw VoiceException(T('i18n.recording_did_not_finish_try'));
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
