import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/data.dart';

void main() {
  const providers = [
    ProviderConfig(
      id: 1,
      name: 'A',
      baseUrl: 'https://example.com',
      model: 'a-default',
      protocol: ApiProtocol.openAi,
    ),
    ProviderConfig(
      id: 2,
      name: 'B',
      baseUrl: 'https://example.org',
      model: 'b-default',
      protocol: ApiProtocol.openAi,
    ),
  ];
  const topics = [
    ChatTopic(
      id: 9,
      title: '最近会话',
      providerId: 2,
      model: 'b-recent',
      updatedAt: 2,
    ),
  ];

  test('cold start restores exact provider and manually entered model ID', () {
    const selection = ChatSelection(1, 'custom/model-id');
    final restored = initialChatSelection(
      providers,
      topics,
      ChatSelection.tryParse(selection.toJson()),
    );
    expect(restored?.providerId, 1);
    expect(restored?.model, 'custom/model-id');
  });

  test('deleted provider falls back to the newest usable conversation', () {
    final restored = initialChatSelection(
      providers,
      topics,
      const ChatSelection(3, 'deleted-model'),
    );
    expect(restored?.providerId, 2);
    expect(restored?.model, 'b-recent');
  });

  test('fresh install and invalid stored value have safe defaults', () {
    expect(initialChatSelection([], topics, null), isNull);
    expect(ChatSelection.tryParse('{"providerId":1,"model":""}'), isNull);
    expect(ChatSelection.tryParse('invalid'), isNull);
    final restored = initialChatSelection(providers, [], null);
    expect(restored?.providerId, 1);
    expect(restored?.model, 'a-default');
  });
}
