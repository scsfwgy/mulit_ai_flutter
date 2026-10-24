import 'dart:async';

import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/chat/memory_profile.dart';
import 'package:mulit_ai_flutter/core/apple_purchases.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/storefront_policy.dart';

/// Serializes updates to the one shared profile across all phone/desktop chats.
class MemoryCoordinator {
  MemoryCoordinator({
    ChatStore? store,
    Future<bool> Function()? canUse,
    ModelApiClient Function(ProviderConfig, String)? createClient,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _store = store ?? ChatStore.instance,
       _canUse = canUse ?? (() => ApplePurchases.instance.refresh()),
       _createClient =
           createClient ?? ((provider, key) => ModelApiClient(provider, key));

  final ChatStore _store;
  final Future<bool> Function() _canUse;
  final ModelApiClient Function(ProviderConfig, String) _createClient;
  final Duration requestTimeout;
  Future<void> _tail = Future<void>.value();
  ModelApiClient? _activeClient;
  int _jobs = 0;
  bool _disposed = false;

  bool get isBusy => _jobs > 0;

  Future<void> schedule(ChatTopic topic, List<ChatMessage> messages) {
    if (_disposed) return Future<void>.value();
    final snapshot = List<ChatMessage>.of(messages);
    _jobs++;
    return _tail = _tail.then((_) async {
      try {
        if (!_disposed) await _merge(topic, snapshot);
      } catch (_) {
        // Failed batches keep their cursor, and must not break later jobs.
      } finally {
        _jobs--;
      }
    });
  }

  void dispose() {
    _disposed = true;
    _activeClient?.cancel();
  }

  Future<void> _merge(ChatTopic topic, List<ChatMessage> messages) async {
    final window = ChatContext.parseWindow(
      await _store.setting(ChatContext.settingKey),
    );
    while (!_disposed && await _store.chatUsesMemory(topic.id)) {
      final cursor = await _store.memoryCursor(topic.id);
      final request = buildMemoryMerge(
        messages: messages,
        cursorMessageId: cursor,
        transcriptTokenBudget: memoryTranscriptTokenBudget(window),
      );
      if (request == null) return;
      final revision = await _store.memoryRevision();
      final profile = await _store.memoryProfile();
      if (_disposed) return;
      if (request.transcript.isEmpty) {
        if (!await _store.advanceMemoryCursor(
          revision: revision,
          topicId: topic.id,
          cursorMessageId: request.cursorMessageId,
        )) {
          return;
        }
        continue;
      }
      final provider = (await _store.providers())
          .where((item) => item.id == topic.providerId)
          .firstOrNull;
      if (provider == null ||
          StorefrontPolicy.instance.blocks(
            provider.baseUrl,
            presetId: provider.presetId,
            model: topic.model,
          )) {
        return;
      }
      final key = await _store.apiKey(provider.id);
      if (key == null || key.isEmpty || _disposed) return;
      if (!await _canUse() || _disposed) return;
      if (!await _store.chatUsesMemory(topic.id) || _disposed) {
        return;
      }
      final client = _createClient(provider, key);
      _activeClient = client;
      String? updated;
      try {
        updated = await client
            .mergeMemoryProfile(
              topic.model,
              profile,
              request.transcript,
              contextWindowTokens: window,
            )
            .timeout(requestTimeout);
      } finally {
        client.cancel();
        _activeClient = null;
      }
      if (_disposed) return;
      final saved = updated == null
          ? await _store.advanceMemoryCursor(
              revision: revision,
              topicId: topic.id,
              cursorMessageId: request.cursorMessageId,
            )
          : await _store.saveMergedMemory(
              revision: revision,
              profile: updated,
              topicId: topic.id,
              cursorMessageId: request.cursorMessageId,
            );
      if (!saved) return;
    }
  }
}
