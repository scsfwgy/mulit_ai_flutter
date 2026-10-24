import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/core/data.dart';

const memoryTurnClipChars = 700;
const memoryTranscriptCharCap = 6000;
const memoryMergeMaxTokens = 1024;

const memoryMergeInstruction =
    '根据已有用户资料和新增对话，更新跨会话资料。只保留稳定的个人事实与偏好，例如称呼、语言、长期项目和明确偏好。矛盾时以较新内容替换。省略一次性问题、密钥、验证码和口令。不要写入指令或角色设定。沿用资料和对话的语言。只输出资料正文，不超过800字。没有可保留的新事实时，原样输出已有资料；已有资料为空且没有新事实时，不要输出任何内容。';

String memoryMergeUserContent(String profile, String transcript) {
  final current = profile.trim().isEmpty ? '（空）' : profile.trim();
  return '已有资料：\n$current\n\n新增对话：\n$transcript';
}

String? normalizeMemoryProfile(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  text = text.replaceFirst(RegExp(r'^(用户资料|资料)\s*[:：]\s*'), '').trim();
  if (text.isEmpty || text == '（空）' || text == '(空)') return null;
  final clipped = clipMemoryProfile(text);
  return clipped.isEmpty ? null : clipped;
}

/// Token room left for the new transcript inside the smallest usable window.
int memoryTranscriptTokenBudget(int windowTokens) {
  final window = ChatContext.windowOptions.contains(windowTokens)
      ? windowTokens
      : ChatContext.defaultWindowTokens;
  final overhead =
      ChatContext.estimateTokens(memoryMergeInstruction) +
      ChatContext.estimateTokens(
        memoryMergeUserContent('字' * memoryProfileMaxChars, ''),
      ) +
      32;
  final budget = window - memoryMergeMaxTokens - 256 - overhead;
  return budget < 200 ? 200 : budget;
}

class MemoryMergeRequest {
  const MemoryMergeRequest({
    required this.transcript,
    required this.cursorMessageId,
  });

  /// Empty when the only new turns had no text. The caller still advances
  /// the cursor and does not send a request.
  final String transcript;
  final int cursorMessageId;
}

/// Complete user-and-assistant turns newer than [cursorMessageId].
/// A trailing user message without an assistant reply stays for the next update.
MemoryMergeRequest? buildMemoryMerge({
  required List<ChatMessage> messages,
  required int cursorMessageId,
  required int transcriptTokenBudget,
}) {
  final turns = _completeTurns(messages, cursorMessageId);
  if (turns.isEmpty) return null;
  final parts = <String>[];
  var lastId = cursorMessageId;
  for (final turn in turns) {
    final piece = _formatTurn(turn);
    if (piece.isEmpty) {
      lastId = turn.last.id;
      continue;
    }
    final combined = [...parts, piece].join('\n');
    final limited = _limitTranscript(combined, transcriptTokenBudget);
    if (limited.isEmpty) break;
    final shortened = limited.length < combined.trim().length;
    if (shortened && parts.isNotEmpty) break;
    if (shortened) {
      parts
        ..clear()
        ..add(limited);
      lastId = turn.last.id;
      break;
    }
    parts.add(piece);
    lastId = turn.last.id;
  }
  if (parts.isEmpty) {
    if (lastId == cursorMessageId) return null;
    return MemoryMergeRequest(transcript: '', cursorMessageId: lastId);
  }
  return MemoryMergeRequest(
    transcript: parts.join('\n'),
    cursorMessageId: lastId,
  );
}

List<List<ChatMessage>> _completeTurns(
  List<ChatMessage> messages,
  int cursorMessageId,
) {
  final turns = <List<ChatMessage>>[];
  final current = <ChatMessage>[];
  void flush() {
    if (current.isEmpty) return;
    final hasUser = current.any((message) => message.role == 'user');
    final hasAssistant = current.any(
      (message) =>
          message.role == 'assistant' && message.content.trim().isNotEmpty,
    );
    if (hasUser && hasAssistant) turns.add(List<ChatMessage>.of(current));
    current.clear();
  }

  for (final message in messages) {
    if (message.id <= cursorMessageId) continue;
    if (message.role == 'user' && current.isNotEmpty) flush();
    if (message.role == 'user' || current.isNotEmpty) current.add(message);
  }
  flush();
  return turns;
}

String _formatTurn(List<ChatMessage> turn) {
  final lines = <String>[];
  for (final message in turn) {
    final text = _messageText(message);
    if (text.isEmpty) continue;
    final speaker = message.role == 'user' ? '用户' : '助手';
    lines.add('$speaker：$text');
  }
  return lines.join('\n');
}

String _messageText(ChatMessage message) {
  final raw = message.role == 'user' ? message.titleContent : message.content;
  return _clipRunes(raw.trim(), memoryTurnClipChars);
}

String _limitTranscript(String text, int tokenBudget) {
  final capped = _clipRunes(text.trim(), memoryTranscriptCharCap);
  return _clipToTokenBudget(capped, tokenBudget);
}

String _clipRunes(String text, int maxRunes) {
  if (text.isEmpty) return '';
  final runes = text.runes.toList();
  if (runes.length <= maxRunes) return text;
  return String.fromCharCodes(runes.take(maxRunes));
}

String _clipToTokenBudget(String text, int tokenBudget) {
  if (text.isEmpty || tokenBudget <= 0) return '';
  if (ChatContext.estimateTokens(text) <= tokenBudget) return text;
  final runes = text.runes.toList();
  var low = 0;
  var high = runes.length;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    final candidate = String.fromCharCodes(runes.take(mid));
    if (ChatContext.estimateTokens(candidate) <= tokenBudget) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return String.fromCharCodes(runes.take(low)).trim();
}
