import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';

ProviderConfig provider(
  HttpServer server, [
  ApiProtocol protocol = ApiProtocol.openAi,
]) => ProviderConfig(
  id: 1,
  name: 'local',
  baseUrl: 'http://127.0.0.1:${server.port}/v1',
  model: 'demo',
  protocol: protocol,
);

ChatMessage message(String role, String text) =>
    ChatMessage(id: 0, topicId: 0, role: role, content: text, createdAt: 0);

void main() {
  test(
    'historical source metadata counts toward the serialized context budget',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = Completer<Map<String, dynamic>>();
      server.listen((request) async {
        seen.complete(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.write(
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n\ndata: [DONE]\n\n',
        );
        await request.response.close();
      });
      final withSources = ChatMessage(
        id: 0,
        topicId: 0,
        role: 'assistant',
        content: 'small answer',
        createdAt: 0,
        searchSources: [
          SearchSource(
            title: '文' * 3000,
            url: 'https://example.com',
            excerpt: '',
          ),
        ],
      );
      var omitted = 0;
      expect(
        await ModelApiClient(provider(server), 'test-key')
            .streamReply(
              [message('user', 'old'), withSources, message('user', 'latest')],
              'demo',
              contextWindowTokens: 8192,
              onContextTrimmed: (count) => omitted = count,
            )
            .join(),
        'ok',
      );
      expect((await seen.future)['messages'], [
        {'role': 'user', 'content': 'latest'},
      ]);
      expect(omitted, 2);
      expect(withSources.searchSources.single.title.length, 3000);
    },
  );

  test(
    'search evidence is budgeted before sending the model request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var searches = 0;
      var modelRequests = 0;
      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path == '/search') {
          searches++;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'results': [
                {
                  'title': 'Evidence',
                  'url': 'https://example.com',
                  'content': '文' * 2000,
                },
              ],
            }),
          );
        } else {
          modelRequests++;
        }
        await request.response.close();
      });
      await expectLater(
        ModelApiClient(provider(server), 'test-key')
            .streamReply(
              [message('user', 'latest question')],
              'demo',
              contextWindowTokens: 8192,
              webSearch: (
                config: SearchProviderConfig(
                  id: 'local-search',
                  name: 'Local',
                  service: SearchService.tavily,
                  endpoint: 'http://127.0.0.1:${server.port}/search',
                ),
                apiKey: 'test-search-key',
              ),
            )
            .join(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.context,
          ),
        ),
      );
      expect(searches, 1);
      expect(modelRequests, 0);
    },
  );
  for (final protocol in ApiProtocol.values) {
    test(
      '$protocol sends recent turns and preserves the system prompt',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final seen = Completer<Map<String, dynamic>>();
        server.listen((request) async {
          request.response.bufferOutput = false;
          seen.complete(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            protocol == ApiProtocol.openAi
                ? 'data: {"choices":[{"delta":{"content":"ok"}}]}\n\ndata: [DONE]\n\n'
                : 'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}\n\ndata: {"type":"message_stop"}\n\n',
          );
          await request.response.close();
        });
        final history = [
          message('user', 'old'),
          message('assistant', '文' * 5000),
          message('user', 'current'),
        ];
        expect(
          await ModelApiClient(provider(server, protocol), 'test-key')
              .streamReply(
                history,
                'demo',
                systemPrompt: 'retain this prompt',
                contextWindowTokens: 8192,
              )
              .join(),
          'ok',
        );
        final body = await seen.future;
        final sent = body['messages'] as List;
        expect(sent.where((item) => item['role'] != 'system').toList(), [
          {'role': 'user', 'content': 'current'},
        ]);
        expect(
          protocol == ApiProtocol.openAi
              ? sent.first['content']
              : body['system'],
          'retain this prompt',
        );
        expect(history.length, 3);
      },
    );
  }

  test(
    'oversized mandatory input is rejected without sending an HTTP request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) {
        requests++;
        request.response.close();
      });
      await expectLater(
        ModelApiClient(provider(server), 'test-key')
            .streamReply(
              [message('user', '文' * 6000)],
              'demo',
              contextWindowTokens: 8192,
            )
            .toList(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiErrorKind.context,
          ),
        ),
      );
      expect(requests, 0);
    },
  );

  for (final partial in [false, true]) {
    test(
      'idle body stops with partial=$partial and does not authorize automatic replay',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          request.response.bufferOutput = false;
          await request.drain<void>();
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            partial
                ? 'data: {"choices":[{"delta":{"content":"kept"}}]}\n\n'
                : ': connected\n\n',
          );
          await request.response.flush();
        });
        final received = <String>[];
        final client = ModelApiClient(
          provider(server),
          'test-key',
          bodyIdleTimeout: const Duration(milliseconds: 100),
        );
        await expectLater(
          () async {
            await for (final chunk in client.streamReply([
              message('user', 'question'),
            ], 'demo')) {
              received.add(chunk);
            }
          }(),
          throwsA(
            isA<ApiException>()
                .having((e) => e.kind, 'kind', ApiErrorKind.network)
                .having((e) => e.retrySafe, 'retrySafe', false),
          ),
        );
        expect(received, partial ? ['kept'] : isEmpty);
      },
    );
  }

  test(
    'SSE heartbeats reset the raw-body idle timer without visible text',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.bufferOutput = false;
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        for (var i = 0; i < 8; i++) {
          request.response.write(': heartbeat\n\n');
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        request.response.write(
          'data: {"choices":[{"delta":{"content":"after thinking"}}]}\n\ndata: [DONE]\n\n',
        );
        await request.response.close();
      });
      expect(
        await ModelApiClient(
          provider(server),
          'test-key',
          bodyIdleTimeout: const Duration(milliseconds: 300),
        ).streamReply([message('user', 'question')], 'demo').join(),
        'after thinking',
      );
    },
  );

  test(
    'Claude message_stop completes even if the server keeps the socket open',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.bufferOutput = false;
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}\n\ndata: {"type":"message_stop"}\n\n',
        );
        await request.response.flush();
      });
      expect(
        await ModelApiClient(
              provider(server, ApiProtocol.anthropic),
              'test-key',
              bodyIdleTimeout: const Duration(milliseconds: 100),
            )
            .streamReply(
              [message('user', 'question')],
              'demo',
              requireComplete: true,
            )
            .join(),
        'ok',
      );
    },
  );

  for (final streamError in [false, true]) {
    test(
      'context limit errors are actionable and do not expose response text (stream=$streamError)',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          request.response.bufferOutput = false;
          await request.drain<void>();
          const error =
              '{"error":{"code":"context_length_exceeded","message":"private-content test-key"}}';
          if (streamError) {
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            request.response.write('data: $error\n\n');
          } else {
            request.response.statusCode = 400;
            request.response.write(error);
          }
          await request.response.close();
        });
        await expectLater(
          ModelApiClient(provider(server), 'test-key')
              .streamReply(
                [message('user', 'question')],
                'demo',
                onUsage: (_) {},
              )
              .join(),
          throwsA(
            isA<ApiException>()
                .having((e) => e.kind, 'kind', ApiErrorKind.context)
                .having(
                  (e) => e.message,
                  'message',
                  ChatContext.serverLimitMessage,
                ),
          ),
        );
      },
    );
  }

  test('a stalled model-list body has the same bounded idle read', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.write('{"data":[');
      await request.response.flush();
    });
    await expectLater(
      ModelApiClient(
        provider(server),
        'test-key',
        bodyIdleTimeout: const Duration(milliseconds: 100),
      ).fetchModels(),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.network),
      ),
    );
  });
}
