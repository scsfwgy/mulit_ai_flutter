import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mulit_ai_flutter/data.dart';
import 'package:mulit_ai_flutter/voice_client.dart';
import 'package:mulit_ai_flutter/voice_request_diagnostics.dart';

Uint8List wav({bool silent = false}) {
  final bytes = Uint8List(52);
  final view = ByteData.sublistView(bytes);
  void tag(int at, String value) =>
      bytes.setRange(at, at + 4, ascii.encode(value));
  tag(0, 'RIFF');
  view.setUint32(4, 44, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, 1, Endian.little);
  view.setUint32(24, 16000, Endian.little);
  view.setUint32(28, 32000, Endian.little);
  view.setUint16(32, 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  view.setUint32(40, 8, Endian.little);
  if (!silent) {
    for (var i = 0; i < 4; i++) {
      view.setInt16(44 + i * 2, [0, 100, -200, 300][i], Endian.little);
    }
  }
  return bytes;
}

void main() {
  test('WAV metadata reports real format, silence and truncated audio', () {
    final info = voiceWavDiagnostics(wav());
    expect(info['sample_rate_hz'], 16000);
    expect(info['channels'], 1);
    expect(info['bits_per_sample'], 16);
    expect(info['data_actual_bytes'], 8);
    expect(info['pcm16_peak'], 300);
    expect(info['pcm16_nonzero_samples'], 3);
    expect(voiceWavDiagnostics(wav(silent: true))['pcm16_peak'], 0);
    final cut = wav().sublist(0, 49);
    expect(voiceWavDiagnostics(cut)['data_truncated'], true);
    expect(voiceWavDiagnostics(Uint8List(0))['container'], 'not_riff_wave');
  });

  test(
    '500 trace matches the sent request and excludes credentials and audio',
    () async {
      final logs = <String>[];
      final oldPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = oldPrint);
      const secret = 'secret-key';
      final audio = wav();
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
        secret,
        client: MockClient((request) async {
          final sent = jsonDecode(request.body);
          expect(sent['model'], 'mimo-v2.5-asr');
          expect(
            sent['messages'][0]['content'][0]['input_audio']['data'],
            'data:audio/wav;base64,${base64Encode(audio)}',
          );
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'internal_error',
                'message': '$secret ${base64Encode(audio)}',
              },
            }),
            500,
          );
        }),
      );
      await expectLater(
        client.transcribe(audio),
        throwsA(isA<VoiceException>()),
      );
      final joined = logs.join('\n');
      expect(joined, contains('mimo-v2.5-asr'));
      expect(joined, contains('internal_error'));
      expect(joined, contains('"sample_rate_hz":16000'));
      expect(joined, contains('"pcm16_peak":300'));
      expect(joined, contains('"http_status":500'));
      expect(joined, isNot(contains(secret)));
      expect(joined, isNot(contains(base64Encode(audio))));
      expect(logs.length, 3);
      final ids = logs.map((line) => line.split(']')[1]).toSet();
      expect(ids.length, 1);
    },
  );

  test('diagnostics omit endpoint credentials, query and synthesis text', () {
    final request =
        http.Request(
            'POST',
            Uri.parse(
              'https://u:secret@example.com/v1/audio/speech?key=secret',
            ),
          )
          ..body = jsonEncode({
            'model': 'tts',
            'input': 'private transcript',
            'voice': 'coral',
          });
    final result = voiceRequestDiagnostics(request);
    expect(
      result['endpoint'],
      startsWith('https://example.com/v1/audio/speech'),
    );
    expect(jsonEncode(result), isNot(contains('secret')));
    expect(jsonEncode(result), isNot(contains('private transcript')));
  });
}
