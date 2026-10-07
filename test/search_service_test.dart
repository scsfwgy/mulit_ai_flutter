import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';

SearchProviderConfig config(HttpServer server, SearchService service) =>
    SearchProviderConfig(
      id: 'search-test',
      name: 'Search',
      service: service,
      endpoint: 'http://127.0.0.1:${server.port}/search',
      maxResults: 3,
      detailed: true,
      timeRange: SearchTimeRange.week,
    );

void jsonResponse(HttpRequest request, Object body) {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  unawaited(request.response.close());
}

const question = ChatMessage(
  id: 1,
  topicId: 1,
  role: 'user',
  content: '今天有什么新闻？',
  createdAt: 0,
);

void main() {
  test('refused search connection can safely switch watch routes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final search = SearchClient(
      config(server, SearchService.tavily),
      'fake-key',
    );
    await server.close(force: true);
    await expectLater(
      search.search('question'),
      throwsA(
        isA<SearchException>()
            .having((error) => error.networkFailure, 'network failure', true)
            .having(
              (error) => error.retrySafe,
              'request never reached service',
              true,
            ),
      ),
    );
  });
  for (final service in SearchService.values) {
    test('${service.name} maps credentials, options and sources', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<Map<String, dynamic>>();
      server.listen((request) async {
        received.complete(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        expect(
          request.headers.value(
            service == SearchService.exa ? 'x-api-key' : 'authorization',
          ),
          service == SearchService.exa
              ? 'fake-search-key'
              : 'Bearer fake-search-key',
        );
        jsonResponse(
          request,
          service == SearchService.bocha
              ? {
                  'code': 200,
                  'data': {
                    'webPages': {
                      'value': [
                        {
                          'name': '新闻',
                          'url': 'https://example.com/news',
                          'summary': '网页资料',
                          'datePublished': '2026-10-05',
                        },
                      ],
                    },
                  },
                }
              : {
                  'results': [
                    {
                      'title': '新闻',
                      'url': 'https://example.com/news',
                      if (service == SearchService.exa)
                        'text': '网页资料'
                      else
                        'content': '网页资料',
                      if (service == SearchService.exa)
                        'publishedDate': '2026-10-05'
                      else
                        'published_date': '2026-10-05',
                    },
                  ],
                },
        );
      });
      final result = await SearchClient(
        config(server, service),
        'fake-search-key',
      ).search(question.content);
      expect(result.sources.single.title, '新闻');
      expect(result.sources.single.publishedAt, '2026-10-05');
      expect(result.context, contains('untrusted'));
      final body = await received.future;
      expect(body['query'], question.content);
      expect(jsonEncode(body), isNot(contains('fake-search-key')));
      switch (service) {
        case SearchService.bocha:
          expect(body['count'], 3);
          expect(body['freshness'], 'oneWeek');
          expect(body['summary'], true);
        case SearchService.tavily:
          expect(body['max_results'], 3);
          expect(body['time_range'], 'week');
          expect(body['search_depth'], 'advanced');
          expect(body['include_answer'], false);
        case SearchService.exa:
          expect(body['numResults'], 3);
          expect(body['type'], 'auto');
          expect(
            DateTime.parse(body['startPublishedDate'] as String).isUtc,
            true,
          );
          expect(body['contents']['text']['maxCharacters'], 2000);
      }
    });
  }

  test(
    'filter unsafe links, deduplicate, redact secrets and bound content',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect((body['query'] as String).runes.length, 1000);
        jsonResponse(request, {
          'results': [
            {'title': 'unsafe', 'url': 'javascript:alert(1)', 'content': 'no'},
            {
              'title': 'credentials',
              'url': 'https://user:password@example.com/',
              'content': 'no',
            },
            {
              'title': 'key in URL',
              'url': 'https://example.com/fake-search-key',
              'content': 'no',
            },
            {
              'title': 'fake-search-key',
              'url': 'https://example.com/a',
              'content': 'fake-search-key ${List.filled(3000, '字').join()}',
            },
            {
              'title': 'duplicate',
              'url': 'https://example.com/a',
              'content': 'no',
            },
            {
              'title': 'empty',
              'url': 'https://example.com/empty',
              'content': '',
            },
          ],
        });
      });
      final result = await SearchClient(
        config(server, SearchService.tavily),
        'fake-search-key',
      ).search(List.filled(1100, '😀').join());
      expect(result.sources.length, 1);
      expect(result.sources.single.excerpt.runes.length, 2000);
      expect(result.sources.single.title, '[已隐藏]');
      expect(result.context, isNot(contains('fake-search-key')));
    },
  );

  test('redirects are rejected without forwarding a key', () async {
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await target.close(force: true);
    });
    var forwarded = false;
    target.listen((request) {
      forwarded = true;
      jsonResponse(request, {});
    });
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 307;
      request.response.headers.set(
        'location',
        'http://127.0.0.1:${target.port}/stolen',
      );
      await request.response.close();
    });
    await expectLater(
      SearchClient(
        config(server, SearchService.tavily),
        'fake-search-key',
      ).search('test'),
      throwsA(
        isA<SearchException>().having(
          (e) => e.message,
          'message',
          contains('307'),
        ),
      ),
    );
    expect(forwarded, false);
  });

  test(
    'provider errors and oversized responses never expose their body',
    () async {
      for (final status in [401, 200]) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        try {
          server.listen((request) async {
            await request.drain<void>();
            request.response.statusCode = status;
            request.response.write(
              status == 401
                  ? 'fake-search-key sensitive-query'
                  : 'x' * (512 * 1024 + 1),
            );
            await request.response.close();
          });
          await expectLater(
            SearchClient(
              config(server, SearchService.exa),
              'fake-search-key',
            ).search('test'),
            throwsA(
              isA<SearchException>().having(
                (e) => e.message,
                'redacted message',
                allOf(
                  isNot(contains('fake-search-key')),
                  isNot(contains('sensitive-query')),
                ),
              ),
            ),
          );
        } finally {
          await server.close(force: true);
        }
      }
    },
  );

  for (final protocol in ApiProtocol.values) {
    test(
      'search grounds ${protocol.name} without changing stored user content',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        Map<String, dynamic>? modelBody;
        var searches = 0;
        server.listen((request) async {
          final body = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          if (request.uri.path == '/search') {
            searches++;
            jsonResponse(request, {
              'results': [
                {
                  'title': '官方资料',
                  'url': 'https://example.com/news',
                  'content': '最新的网页资料',
                },
              ],
            });
          } else {
            modelBody = body;
            expect(
              request.headers.value(
                protocol == ApiProtocol.openAi ? 'authorization' : 'x-api-key',
              ),
              protocol == ApiProtocol.openAi
                  ? 'Bearer fake-model-key'
                  : 'fake-model-key',
            );
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            final event = protocol == ApiProtocol.openAi
                ? {
                    'choices': [
                      {
                        'delta': {
                          'content': '回答 [1](https://example.com/news)',
                        },
                      },
                    ],
                  }
                : {
                    'type': 'content_block_delta',
                    'delta': {
                      'type': 'text_delta',
                      'text': '回答 [1](https://example.com/news)',
                    },
                  };
            request.response.add(utf8.encode('data: ${jsonEncode(event)}\n\n'));
            request.response.write(
              protocol == ApiProtocol.openAi
                  ? 'data: [DONE]\n\n'
                  : 'data: {"type":"message_stop"}\n\n',
            );
            await request.response.close();
          }
        });
        List<SearchSource>? sources;
        final provider = ProviderConfig(
          id: 1,
          name: 'Model',
          baseUrl: 'http://127.0.0.1:${server.port}',
          model: 'demo',
          protocol: protocol,
        );
        final reply = await ModelApiClient(provider, 'fake-model-key')
            .streamReply(
              [question],
              'demo',
              systemPrompt: '全局提示词',
              requireComplete: true,
              webSearch: (
                config: config(server, SearchService.tavily),
                apiKey: 'fake-search-key',
              ),
              onSearchResults: (value) => sources = value,
            )
            .join();
        expect(searches, 1);
        expect(reply, contains('[1](https://example.com/news)'));
        expect(sources!.single.url, 'https://example.com/news');
        expect(
          (modelBody!['messages'] as List).last['content'],
          contains('最新的网页资料'),
        );
        expect(jsonEncode(modelBody), isNot(contains('fake-search-key')));
        expect(question.content, '今天有什么新闻？');
        expect(
          protocol == ApiProtocol.openAi
              ? (modelBody!['messages'] as List).first['content']
              : modelBody!['system'],
          contains('全局提示词'),
        );
      },
    );
  }

  test('empty search results prevent any model request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var modelRequests = 0;
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path != '/search') modelRequests++;
      jsonResponse(request, {'results': []});
    });
    final provider = ProviderConfig(
      id: 1,
      name: 'Model',
      baseUrl: 'http://127.0.0.1:${server.port}',
      model: 'demo',
      protocol: ApiProtocol.openAi,
    );
    await expectLater(
      ModelApiClient(provider, 'fake-model-key')
          .streamReply(
            [question],
            'demo',
            webSearch: (
              config: config(server, SearchService.tavily),
              apiKey: 'fake-search-key',
            ),
          )
          .join(),
      throwsA(isA<SearchException>()),
    );
    expect(modelRequests, 0);
  });

  test('stop during search cancels it before a model request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final started = Completer<void>();
    var modelRequests = 0;
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/search') {
        started.complete();
      } else {
        modelRequests++;
        jsonResponse(request, {});
      }
    });
    final provider = ProviderConfig(
      id: 1,
      name: 'Model',
      baseUrl: 'http://127.0.0.1:${server.port}',
      model: 'demo',
      protocol: ApiProtocol.openAi,
    );
    final client = ModelApiClient(provider, 'fake-model-key');
    final outcome = expectLater(
      client
          .streamReply(
            [question],
            'demo',
            webSearch: (
              config: config(server, SearchService.tavily),
              apiKey: 'fake-search-key',
            ),
          )
          .join(),
      throwsA(isA<SearchException>()),
    );
    await started.future;
    client.cancel();
    await outcome;
    expect(modelRequests, 0);
  });

  test('usage compatibility retry reuses search results', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var searches = 0;
    var models = 0;
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      if (request.uri.path == '/search') {
        searches++;
        jsonResponse(request, {
          'results': [
            {'url': 'https://example.com', 'title': '资料', 'content': '依据'},
          ],
        });
      } else {
        models++;
        expect((body['messages'] as List).last['content'], contains('依据'));
        if (body.containsKey('stream_options')) {
          request.response.statusCode = 400;
          jsonResponse(request, {
            'error': {'message': 'stream_options unsupported'},
          });
        } else {
          request.response.write(
            'data: {"choices":[{"delta":{"content":"answer"}}]}\n\ndata: [DONE]\n\n',
          );
          await request.response.close();
        }
      }
    });
    final provider = ProviderConfig(
      id: 1,
      name: 'Model',
      baseUrl: 'http://127.0.0.1:${server.port}',
      model: 'demo',
      protocol: ApiProtocol.openAi,
    );
    expect(
      await ModelApiClient(provider, 'fake-model-key')
          .streamReply(
            [question],
            'demo',
            onUsage: (_) {},
            webSearch: (
              config: config(server, SearchService.tavily),
              apiKey: 'fake-search-key',
            ),
          )
          .join(),
      'answer',
    );
    expect(searches, 1);
    expect(models, 2);
  });
}
