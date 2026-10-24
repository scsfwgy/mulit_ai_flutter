import 'dart:convert';

class ChatAttachment {
  const ChatAttachment({
    required this.name,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.estimatedTokens,
  });

  final String name;
  final String fileName;
  final String mimeType;
  final int size;
  final int estimatedTokens;
  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';
  bool get isText => mimeType == 'text/plain';
  bool get isGenericFile => !isImage && !isPdf && !isText;

  Map<String, Object> toJson() => {
    'name': name,
    'fileName': fileName,
    'mimeType': mimeType,
    'size': size,
    'estimatedTokens': estimatedTokens,
  };

  static String? encode(List<ChatAttachment> attachments) => attachments.isEmpty
      ? null
      : jsonEncode(attachments.map((a) => a.toJson()).toList());

  static List<ChatAttachment> decode(String? value) => value == null
      ? const []
      : (jsonDecode(value) as List)
            .map(
              (item) => ChatAttachment(
                name: item['name'] as String,
                fileName: item['fileName'] as String,
                mimeType: item['mimeType'] as String,
                size: item['size'] as int,
                estimatedTokens: item['estimatedTokens'] as int,
              ),
            )
            .toList();
}
