import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mulit_ai_flutter/data.dart';
import 'package:mulit_ai_flutter/voice_client.dart';

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
          expect(request.body, contains('name="file"'));
          expect(request.body, contains('name="model"'));
          return http.Response.bytes(
            utf8.encode(jsonEncode({'text': '  你好  '})),
            200,
          );
        }),
      );
      expect(await client.transcribe(Uint8List.fromList([1, 2, 3])), '你好');
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
    expect(await client.transcribe(Uint8List.fromList([1])), '测试文字');
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
    expect(await client.transcribe(Uint8List.fromList([1])), '火山测试');
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
        client.transcribe(Uint8List.fromList([1])),
        throwsA(
          predicate(
            (e) => e is VoiceException && !e.message.contains('secret-key'),
          ),
        ),
      );
    },
  );
}
