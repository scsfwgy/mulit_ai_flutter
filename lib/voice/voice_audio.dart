import 'dart:convert';
import 'dart:typed_data';

import 'package:mulit_ai_flutter/i18n/strings.dart';

class VoiceException implements Exception {
  const VoiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

Uint8List pcm16VoiceWav(Uint8List pcm, {int sampleRate = 16000}) {
  if (pcm.isEmpty) {
    throw VoiceException(T('i18n.no_audio_captured_check'));
  }
  if (pcm.length.isOdd) {
    throw VoiceException(T('i18n.incomplete_audio_data_try_again'));
  }
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
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  wav.setRange(44, wav.length, pcm);
  return wav;
}
