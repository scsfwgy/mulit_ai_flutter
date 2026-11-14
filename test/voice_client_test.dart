import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/voice/voice_client.dart';
import 'package:mulit_ai_flutter/voice/voice_recording.dart';

VoiceProviderConfig config(VoiceProtocol protocol) => VoiceProviderConfig(
  id: 'test',
  name: 'Test',
  protocol: protocol,
  baseUrl: 'http://127.0.0.1:8000',
  asrModel: protocol == VoiceProtocol.doubao ? 'volc.bigasr.auc_turbo' : 'asr',
  ttsModel: protocol == VoiceProtocol.doubao ? 'seed-tts-2.0' : 'tts',
  voice: 'voice',
);

void main() {
  test('DeepSeek ASR uploads only a file and returns the transcript', () async {
    final client = VoiceClient(
      config(VoiceProtocol.deepseek),
      'test-key',
      client: MockClient((request) async {
        expect(request.url.path, '/tools/asr');
        expect(request.headers['authorization'], 'Bearer test-key');
        expect(request.followRedirects, false);
        final body = utf8.decode(request.bodyBytes, allowMalformed: true);
        expect(body, contains('name="file"; filename="speech.wav"'));
        expect(body, isNot(contains('name="model"')));
        return http.Response('{"text":"hello","duration_ms":600}', 200);
      }),
    );
    addTearDown(client.close);
    expect(await client.transcribe(pcm16VoiceWav(Uint8List(19200))), 'hello');
  });

  test('DeepSeek rejects overlong recordings before uploading', () async {
    final client = VoiceClient(
      config(VoiceProtocol.deepseek),
      'key',
      client: MockClient((_) async => throw StateError('must not upload')),
    );
    addTearDown(client.close);
    await expectLater(
      client.transcribe(pcm16VoiceWav(Uint8List(32000 * 121))),
      throwsA(isA<VoiceException>()),
    );
  });

  test('DeepSeek TTS sends voice_id and receives WAV bytes', () async {
    final client = VoiceClient(
      config(VoiceProtocol.deepseek),
      'test-key',
      client: MockClient((request) async {
        expect(request.url.path, '/tools/tts');
        expect(request.headers['authorization'], 'Bearer test-key');
        expect(request.followRedirects, false);
        expect(jsonDecode(request.body), {
          'text': 'hello',
          'voice_id': 'voice',
          'format': 'pcm',
          'filter_markdown': true,
        });
        return http.Response.bytes(
          [82, 73, 70, 70],
          200,
          headers: {'content-type': 'audio/pcm'},
        );
      }),
    );
    addTearDown(client.close);
    final wav = await client.synthesize('hello');
    expect(wav.sublist(44), [82, 73, 70, 70]);
    final header = ByteData.sublistView(wav);
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(header.getUint32(4, Endian.little), wav.length - 8);
    expect(header.getUint32(24, Endian.little), 24000);
    expect(header.getUint32(28, Endian.little), 48000);
    expect(header.getUint32(40, Endian.little), 4);
    expect(client.config.audioFormat, 'wav');
    expect(
      VoiceProviderConfig.fromJson(client.config.toJson()).protocol,
      VoiceProtocol.deepseek,
    );
  });

  test('DeepSeek rejects empty or incomplete PCM before playback', () async {
    for (final bytes in [
      <int>[],
      [1],
    ]) {
      final client = VoiceClient(
        config(VoiceProtocol.deepseek),
        'key',
        client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      addTearDown(client.close);
      await expectLater(
        client.synthesize('hello'),
        throwsA(isA<VoiceException>()),
      );
    }
  });

  test(
    'OpenAI transcription uses multipart file and returns verified text',
    () async {
      final client = VoiceClient(
        config(VoiceProtocol.openAi),
        'test-key',
        client: MockClient((request) async {
          expect(request.url.path, '/audio/transcriptions');
          expect(request.headers['authorization'], 'Bearer test-key');
          expect(
            request.headers['content-type'],
            contains('multipart/form-data'),
          );
          expect(
            utf8.decode(request.bodyBytes, allowMalformed: true),
            contains('name="file"'),
          );
          expect(
            utf8.decode(request.bodyBytes, allowMalformed: true),
            contains('name="model"'),
          );
          return http.Response.bytes(
            utf8.encode(jsonEncode({'text': '  你好  '})),
            200,
          );
        }),
      );
      expect(
        await client.transcribe(
          pcm16VoiceWav(Uint8List.fromList([1, 2, 3, 4])),
        ),
        '你好',
      );
    },
  );

  test('MiMo sends audio data URL and reads assistant transcript', () async {
    final client = VoiceClient(
      config(VoiceProtocol.mimo),
      'test-key',
      client: MockClient((request) async {
        expect(request.url.path, '/chat/completions');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final audio =
            (body['messages'][0]['content'][0]['input_audio']['data']
                as String);
        expect(audio, startsWith('data:audio/wav;base64,'));
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '测试文字'},
                },
              ],
            }),
          ),
          200,
        );
      }),
    );
    expect(
      await client.transcribe(pcm16VoiceWav(Uint8List.fromList([1, 2]))),
      '测试文字',
    );
  });

  test('Doubao uses separate speech key and resource headers', () async {
    final client = VoiceClient(
      config(VoiceProtocol.doubao),
      'speech-key',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v3/auc/bigmodel/recognize/flash');
        expect(request.headers['x-api-key'], 'speech-key');
        expect(request.headers['x-api-resource-id'], 'volc.bigasr.auc_turbo');
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'result': {'text': '火山测试'},
            }),
          ),
          200,
          headers: {'x-api-status-code': '20000000'},
        );
      }),
    );
    expect(
      await client.transcribe(pcm16VoiceWav(Uint8List.fromList([1, 2]))),
      '火山测试',
    );
  });

  test('MiMo TTS reads base64 audio without using system speech', () async {
    final client = VoiceClient(
      config(VoiceProtocol.mimo),
      'key',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['messages'][0]['role'], 'assistant');
        expect(body['audio']['format'], 'wav');
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'audio': {
                    'data': base64Encode([1, 2, 3]),
                  },
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    expect(await client.synthesize('你好'), [1, 2, 3]);
  });

  test('Doubao TTS combines SSE audio chunks', () async {
    final client = VoiceClient(
      config(VoiceProtocol.doubao),
      'key',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v3/tts/unidirectional/sse');
        expect(request.headers['x-api-resource-id'], 'seed-tts-2.0');
        return http.Response(
          'data: {"code":0,"data":"AQI="}\n\ndata: {"code":0,"data":"Aw=="}\n',
          200,
        );
      }),
    );
    expect(await client.synthesize('你好'), [1, 2, 3]);
  });

  test(
    'ASR 500 identifies the server failure and keeps only a safe code',
    () async {
      final client = VoiceClient(
        config(VoiceProtocol.mimo),
        'secret-key',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'internal_error',
                'message': 'audio data secret-key',
              },
            }),
            500,
          ),
        ),
      );
      await expectLater(
        client.transcribe(pcm16VoiceWav(Uint8List.fromList([1, 2]))),
        throwsA(
          predicate(
            (e) =>
                e is VoiceException &&
                e.message == '语音识别请求失败（HTTP 500），服务端处理失败，请稍后重试（internal_error）',
          ),
        ),
      );
    },
  );

  test('speech errors separate synthesis, quota and credentials', () async {
    for (final status in [401, 429, 503]) {
      var count = 0;
      final client = VoiceClient(
        config(VoiceProtocol.openAi),
        'secret-key',
        client: MockClient((_) async {
          count++;
          return http.Response('secret-key', status);
        }),
      );
      await expectLater(
        client.synthesize('hello'),
        throwsA(
          predicate(
            (e) =>
                e is VoiceException &&
                e.message.startsWith('语音朗读请求失败') &&
                !e.message.contains('secret-key') &&
                (status == 401
                    ? e.message.contains('密钥')
                    : !e.message.contains('密钥')),
          ),
        ),
      );
      expect(count, 1);
    }
  });

  test('ASR drops unsafe codes and limits oversized error responses', () async {
    for (final response in [
      jsonEncode({
        'error': {'code': 'secret-key'},
      }),
      jsonEncode({
        'error': {'code': 'data:audio/wav;base64,AQ=='},
      }),
      'secret-key' * 2000,
    ]) {
      final client = VoiceClient(
        config(VoiceProtocol.mimo),
        'secret-key',
        client: MockClient((_) async => http.Response(response, 500)),
      );
      await expectLater(
        client.transcribe(pcm16VoiceWav(Uint8List.fromList([1, 2]))),
        throwsA(
          predicate(
            (e) =>
                e is VoiceException &&
                e.message == '语音识别请求失败（HTTP 500），服务端处理失败，请稍后重试',
          ),
        ),
      );
    }
  });

  test(
    'invalid transcripts and error responses do not expose secret',
    () async {
      expect(() => validateTranscript(' \n '), throwsA(isA<VoiceException>()));
      final client = VoiceClient(
        config(VoiceProtocol.mimo),
        'secret-key',
        client: MockClient(
          (_) async => http.Response('secret-key server error', 401),
        ),
      );
      await expectLater(
        client.transcribe(pcm16VoiceWav(Uint8List.fromList([1, 2]))),
        throwsA(
          predicate(
            (e) => e is VoiceException && !e.message.contains('secret-key'),
          ),
        ),
      );
    },
  );
}
