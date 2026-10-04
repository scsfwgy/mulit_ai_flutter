import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mulit_ai_flutter/data.dart';
import 'package:mulit_ai_flutter/voice_client.dart';
import 'package:mulit_ai_flutter/voice_recording.dart';
import 'package:mulit_ai_flutter/voice_request_diagnostics.dart';

void main() {
  test(
    'PCM capture waits for final stream frames and writes exact WAV sizes',
    () async {
      final stream = StreamController<Uint8List>();
      final recording = PcmVoiceRecording(stream.stream);
      stream.add(Uint8List.fromList([1, 2]));
      final finish = recording.finish();
      stream.add(Uint8List.fromList([3, 4, 5, 6]));
      await stream.close();
      final wav = await finish;
      expect(wav.sublist(44), [1, 2, 3, 4, 5, 6]);
      final header = ByteData.sublistView(wav);
      expect(header.getUint32(4, Endian.little), wav.length - 8);
      expect(header.getUint32(40, Endian.little), 6);
      expect(voiceWavDiagnostics(wav)['data_actual_bytes'], 6);
    },
  );

  test('empty and interrupted capture cannot produce an upload', () async {
    final stream = StreamController<Uint8List>();
    final recording = PcmVoiceRecording(stream.stream);
    await stream.close();
    await expectLater(recording.finish(), throwsA(isA<VoiceException>()));
    final failedStream = StreamController<Uint8List>();
    final failedRecording = PcmVoiceRecording(failedStream.stream);
    failedStream.addError(StateError('capture failed'));
    await failedStream.close();
    await expectLater(failedRecording.finish(), throwsA(isA<VoiceException>()));
    expect(() => pcm16VoiceWav(Uint8List(1)), throwsA(isA<VoiceException>()));
  });

  test(
    'cancelled capture discards frames; silent PCM remains valid audio',
    () async {
      final stream = StreamController<Uint8List>();
      final recording = PcmVoiceRecording(stream.stream);
      stream.add(Uint8List.fromList([1, 2]));
      await recording.discard();
      await stream.close();
      await expectLater(recording.finish(), throwsA(isA<VoiceException>()));
      final silent = pcm16VoiceWav(Uint8List(32000));
      expect(voiceWavDiagnostics(silent)['duration_ms'], 1000);
      expect(voiceWavDiagnostics(silent)['pcm16_peak'], 0);
    },
  );

  test(
    'the reported 4096-byte iPhone header is rejected before HTTP',
    () async {
      final empty = Uint8List(4096);
      final header = ByteData.sublistView(empty);
      void tag(int offset, String text) =>
          empty.setRange(offset, offset + 4, ascii.encode(text));
      tag(0, 'RIFF');
      header.setUint32(4, 4088, Endian.little);
      tag(8, 'WAVE');
      tag(12, 'JUNK');
      header.setUint32(16, 28, Endian.little);
      tag(48, 'fmt ');
      header.setUint32(52, 16, Endian.little);
      header.setUint16(56, 1, Endian.little);
      header.setUint16(58, 1, Endian.little);
      header.setUint32(60, 16000, Endian.little);
      header.setUint32(64, 32000, Endian.little);
      header.setUint16(68, 2, Endian.little);
      header.setUint16(70, 16, Endian.little);
      tag(72, 'FLLR');
      header.setUint32(76, 4008, Endian.little);
      tag(4088, 'data');
      expect(voiceWavDiagnostics(empty)['chunks'], [
        'JUNK',
        'fmt ',
        'FLLR',
        'data',
      ]);
      var requests = 0;
      final client = VoiceClient(
        const VoiceProviderConfig(
          id: 'test',
          name: 'MiMo',
          protocol: VoiceProtocol.mimo,
          baseUrl: 'https://example.com/v1',
          asrModel: 'mimo-v2.5-asr',
          ttsModel: 'tts',
          voice: 'voice',
        ),
        'test-key',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
      await expectLater(
        client.transcribe(empty),
        throwsA(
          predicate(
            (error) =>
                error is VoiceException && error.message.contains('没有有效音频数据'),
          ),
        ),
      );
      expect(requests, 0);
    },
  );
}
