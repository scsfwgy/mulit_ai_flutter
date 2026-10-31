import 'dart:convert';

import 'package:mulit_ai_flutter/core/chat_attachment.dart';

String chatDraftKey({int? topicId, int? projectId}) => topicId != null
    ? 'chat_draft:topic:$topicId'
    : 'chat_draft:new:${projectId ?? 0}';

class ChatDraft {
  const ChatDraft({this.text = '', this.attachments = const []});
  final String text;
  final List<ChatAttachment> attachments;
  bool get isEmpty => text.isEmpty && attachments.isEmpty;
  String encode() => jsonEncode({
    'text': text,
    'attachments': [for (final a in attachments) a.toJson()],
  });
  static ChatDraft decode(String? value) {
    if (value == null) return const ChatDraft();
    final json = jsonDecode(value) as Map<String, dynamic>;
    return ChatDraft(
      text: json['text'] as String,
      attachments: ChatAttachment.decode(jsonEncode(json['attachments'])),
    );
  }
}
