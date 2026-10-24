import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/chat/memory_coordinator.dart';
import 'package:mulit_ai_flutter/core/data.dart';

const _provider = ProviderConfig(
  id: 1,
  name: 'test',
  baseUrl: 'http://127.0.0.1/v1',
  model: 'demo',
  protocol: ApiProtocol.openAi,
);
ChatTopic _topic(int id) => ChatTopic(
  id: id,
  title: 'test',
  providerId: 1,
  model: 'demo',
  updatedAt: 0,
);
List<ChatMessage> _messages(int topicId, {int count = 2}) => [
  for (var i = 1; i <= count; i++)
    ChatMessage(
      id: i,
      topicId: topicId,
      role: i.isOdd ? 'user' : 'assistant',
      content: '字' * 700,
      createdAt: i,
    ),
];

class _Store extends Fake implements ChatStore {
  bool enabled = true;
  int revision = 0;
  String profile = 'initial';
  final cursors = <int, int>{};
  @override
  Future<String?> setting(String key) async => null;
  @override
  Future<bool> chatUsesMemory(int topicId) async => enabled;
  @override
  Future<int> memoryCursor(int topicId) async => cursors[topicId] ?? 0;
  @override
  Future<int> memoryRevision() async => revision;
  @override
  Future<String> memoryProfile() async => profile;
  @override
  Future<List<ProviderConfig>> providers() async => [_provider];
  @override
  Future<String?> apiKey(int providerId) async => 'test-key';
  @override
  Future<bool> saveMergedMemory({
    required int revision,
    required String profile,
    required int topicId,
    required int cursorMessageId,
  }) async {
    if (!enabled || revision != this.revision) return false;
    this.profile = profile;
    cursors[topicId] = cursorMessageId;
    return true;
  }

  @override
  Future<bool> advanceMemoryCursor({
    required int revision,
    required int topicId,
    required int cursorMessageId,
  }) => saveMergedMemory(
    revision: revision,
    profile: profile,
    topicId: topicId,
    cursorMessageId: cursorMessageId,
  );
}

class _Client extends ModelApiClient {
  _Client(this.merge) : super(_provider, 'test-key');
  final Future<String?> Function(String profile, String transcript) merge;
  bool cancelled = false;
  @override
  Future<String?> mergeMemoryProfile(
    String model,
    String profile,
    String transcript, {
    int contextWindowTokens = ChatContext.defaultWindowTokens,
  }) => merge(profile, transcript);
  @override
  void cancel() {
    cancelled = true;
    super.cancel();
  }
}

void main() {
  test(
    'one leave drains every batch using the previous batch profile',
    () async {
      final store = _Store();
      final profiles = <String>[];
      final coordinator = MemoryCoordinator(
        store: store,
        canUse: () async => true,
        createClient: (_, _) => _Client((profile, transcript) async {
          profiles.add(profile);
          return 'batch ${profiles.length}';
        }),
      );
      addTearDown(coordinator.dispose);
      await coordinator.schedule(_topic(1), _messages(1, count: 20));
      expect(store.cursors[1], 20);
      expect(profiles, ['initial', 'batch 1', 'batch 2']);
      expect(store.profile, 'batch 3');
      expect(coordinator.isBusy, isFalse);
    },
  );

  test(
    'jobs are serialized and capture the messages at scheduling time',
    () async {
      final store = _Store();
      final started = Completer<void>();
      final first = Completer<String?>();
      final profiles = <String>[];
      final coordinator = MemoryCoordinator(
        store: store,
        canUse: () async => true,
        createClient: (_, _) => _Client((profile, transcript) async {
          profiles.add(profile);
          if (profiles.length == 1) {
            started.complete();
            return first.future;
          }
          return 'second';
        }),
      );
      addTearDown(coordinator.dispose);
      final messages = _messages(1);
      final a = coordinator.schedule(_topic(1), messages);
      messages.clear();
      final b = coordinator.schedule(_topic(2), _messages(2));
      await started.future;
      expect(profiles, ['initial']);
      expect(coordinator.isBusy, isTrue);
      first.complete('first');
      await Future.wait([a, b]);
      expect(profiles, ['initial', 'first']);
      expect(store.cursors, {1: 2, 2: 2});
      expect(store.profile, 'second');
      expect(coordinator.isBusy, isFalse);
    },
  );

  for (final timeout in [false, true]) {
    test(
      'failed batch preserves cursor and the next job can retry (timeout=$timeout)',
      () async {
        final store = _Store();
        final clients = <_Client>[];
        final coordinator = MemoryCoordinator(
          store: store,
          canUse: () async => true,
          requestTimeout: const Duration(milliseconds: 20),
          createClient: (_, _) {
            final fail = clients.isEmpty;
            final client = _Client((_, _) async {
              if (!fail) return 'retried';
              if (timeout) return Completer<String?>().future;
              throw const ApiException('failed');
            });
            clients.add(client);
            return client;
          },
        );
        addTearDown(coordinator.dispose);
        await coordinator.schedule(_topic(1), _messages(1));
        expect(store.cursors, isEmpty);
        expect(store.profile, 'initial');
        expect(clients.single.cancelled, isTrue);
        await coordinator.schedule(_topic(1), _messages(1));
        expect(store.cursors[1], 2);
        expect(store.profile, 'retried');
        expect(coordinator.isBusy, isFalse);
      },
    );
  }

  for (final manualEdit in [false, true]) {
    test(
      'changed memory state rejects in-flight results and stops batches (manualEdit=$manualEdit)',
      () async {
        final store = _Store();
        final started = Completer<void>();
        final response = Completer<String?>();
        var requests = 0;
        final coordinator = MemoryCoordinator(
          store: store,
          canUse: () async => true,
          createClient: (_, _) => _Client((_, _) {
            requests++;
            started.complete();
            return response.future;
          }),
        );
        addTearDown(coordinator.dispose);
        final job = coordinator.schedule(_topic(1), _messages(1, count: 20));
        await started.future;
        if (manualEdit) {
          store.revision++;
          store.profile = 'manual';
        } else {
          store.enabled = false;
        }
        response.complete('obsolete');
        await job;
        expect(store.cursors, isEmpty);
        expect(store.profile, manualEdit ? 'manual' : 'initial');
        expect(requests, 1);
      },
    );
  }

  test(
    'successful empty summaries advance cursors without changing the profile',
    () async {
      final store = _Store();
      var requests = 0;
      final coordinator = MemoryCoordinator(
        store: store,
        canUse: () async => true,
        createClient: (_, _) => _Client((_, _) async {
          requests++;
          return null;
        }),
      );
      addTearDown(coordinator.dispose);
      await coordinator.schedule(_topic(1), _messages(1, count: 20));
      await coordinator.schedule(_topic(1), _messages(1, count: 20));
      expect(store.profile, 'initial');
      expect(store.cursors[1], 20);
      expect(requests, 3);
    },
  );

  test(
    'dispose cancels the active client, skips its result and queued jobs',
    () async {
      final store = _Store();
      final started = Completer<void>();
      final response = Completer<String?>();
      final clients = <_Client>[];
      final coordinator = MemoryCoordinator(
        store: store,
        canUse: () async => true,
        createClient: (_, _) {
          final client = _Client((_, _) {
            started.complete();
            return response.future;
          });
          clients.add(client);
          return client;
        },
      );
      final a = coordinator.schedule(_topic(1), _messages(1));
      final b = coordinator.schedule(_topic(2), _messages(2));
      await started.future;
      coordinator.dispose();
      expect(clients.single.cancelled, isTrue);
      response.complete('discarded');
      await Future.wait([a, b]);
      await coordinator.schedule(_topic(3), _messages(3));
      expect(clients, hasLength(1));
      expect(store.cursors, isEmpty);
      expect(store.profile, 'initial');
      expect(coordinator.isBusy, isFalse);
    },
  );

  test(
    'denied permission leaves the batch available for a later retry',
    () async {
      final store = _Store();
      var requests = 0;
      final coordinator = MemoryCoordinator(
        store: store,
        canUse: () async => false,
        createClient: (_, _) {
          requests++;
          return _Client((_, _) async => 'unexpected');
        },
      );
      addTearDown(coordinator.dispose);
      await coordinator.schedule(_topic(1), _messages(1));
      expect(requests, 0);
      expect(store.cursors, isEmpty);
      expect(store.profile, 'initial');
      expect(coordinator.isBusy, isFalse);
    },
  );

  test('permission checks cannot start a request after disposal', () async {
    final store = _Store();
    final checking = Completer<void>();
    final permission = Completer<bool>();
    var requests = 0;
    final coordinator = MemoryCoordinator(
      store: store,
      canUse: () {
        checking.complete();
        return permission.future;
      },
      createClient: (_, _) {
        requests++;
        return _Client((_, _) async => 'unexpected');
      },
    );
    final job = coordinator.schedule(_topic(1), _messages(1));
    await checking.future;
    coordinator.dispose();
    permission.complete(true);
    await job;
    expect(requests, 0);
    expect(store.cursors, isEmpty);
    expect(coordinator.isBusy, isFalse);
  });
}
