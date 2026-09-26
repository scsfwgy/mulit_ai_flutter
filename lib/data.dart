import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

enum ApiProtocol {
  openAi('openai_chat', 'OpenAI 兼容'),
  anthropic('anthropic_messages', 'Claude Messages');

  const ApiProtocol(this.value, this.label);
  final String value;
  final String label;

  static ApiProtocol parse(String value) => ApiProtocol.values.firstWhere(
    (item) => item.value == value,
    orElse: () => throw const FormatException('不支持的协议'),
  );
}

class ProviderPreset {
  const ProviderPreset(
    this.name,
    this.baseUrl,
    this.model,
    this.protocol,
    this.color,
    this.initial,
  );
  final String name;
  final String baseUrl;
  final String model;
  final ApiProtocol protocol;
  final int color;
  final String initial;
}

const providerPresets = <ProviderPreset>[
  ProviderPreset(
    'OpenAI',
    'https://api.openai.com/v1',
    'gpt-4.1-mini',
    ApiProtocol.openAi,
    0xFF121826,
    'O',
  ),
  ProviderPreset(
    'Claude',
    'https://api.anthropic.com/v1',
    'claude-sonnet-5',
    ApiProtocol.anthropic,
    0xFFC57B55,
    'C',
  ),
  ProviderPreset(
    'DeepSeek',
    'https://api.deepseek.com',
    'deepseek-flash',
    ApiProtocol.openAi,
    0xFF4A73CE,
    'D',
  ),
  ProviderPreset(
    'GLM 智谱',
    'https://open.bigmodel.cn/api/paas/v4',
    'glm-4.5',
    ApiProtocol.openAi,
    0xFF7958CB,
    'G',
  ),
  ProviderPreset(
    '千问 Qwen',
    'https://dashscope.aliyuncs.com/compatible-mode/v1',
    'qwen-plus',
    ApiProtocol.openAi,
    0xFF8A66D7,
    'Q',
  ),
];

String validateBaseUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('请输入有效的 API 根地址');
  }
  final local = {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host);
  if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
    throw const FormatException('API 地址必须使用 HTTPS；模拟器本机地址可用 HTTP');
  }
  return input.trim().replaceAll(RegExp(r'/+$'), '');
}

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.protocol,
  });
  final int id;
  final String name;
  final String baseUrl;
  final String model;
  final ApiProtocol protocol;

  ProviderConfig copyWith({
    int? id,
    String? name,
    String? baseUrl,
    String? model,
    ApiProtocol? protocol,
  }) => ProviderConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    protocol: protocol ?? this.protocol,
  );

  Map<String, Object?> toMap() => {
    'name': name,
    'base_url': baseUrl,
    'model': model,
    'protocol': protocol.value,
  };

  Map<String, Object?> toImportJson() => {
    'name': name,
    'protocol': protocol.value,
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': '',
  };

  factory ProviderConfig.fromMap(Map<String, Object?> map) => ProviderConfig(
    id: map['id'] as int,
    name: map['name'] as String,
    baseUrl: map['base_url'] as String,
    model: map['model'] as String,
    protocol: ApiProtocol.parse(map['protocol'] as String),
  );

  static ({ProviderConfig config, String key}) fromImportJson(
    String source, {
    int id = 0,
  }) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('配置必须是 JSON 对象');
    }
    final name = (decoded['name'] as String?)?.trim() ?? '';
    final model = (decoded['model'] as String?)?.trim() ?? '';
    final key = (decoded['apiKey'] as String?)?.trim() ?? '';
    if (name.isEmpty || model.isEmpty) {
      throw const FormatException('名称和模型不能为空');
    }
    final protocol = ApiProtocol.parse(decoded['protocol'] as String? ?? '');
    final baseUrl = validateBaseUrl(decoded['baseUrl'] as String? ?? '');
    return (
      config: ProviderConfig(
        id: id,
        name: name,
        baseUrl: baseUrl,
        model: model,
        protocol: protocol,
      ),
      key: key,
    );
  }
}

class ChatTopic {
  const ChatTopic({
    required this.id,
    required this.title,
    this.providerId,
    required this.model,
    required this.updatedAt,
  });
  final int id;
  final String title;
  final int? providerId;
  final String model;
  final int updatedAt;

  factory ChatTopic.fromMap(Map<String, Object?> map) => ChatTopic(
    id: map['id'] as int,
    title: map['title'] as String,
    providerId: map['provider_id'] as int?,
    model: map['model'] as String,
    updatedAt: map['updated_at'] as int,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.topicId,
    required this.role,
    required this.content,
    required this.createdAt,
  });
  final int id;
  final int topicId;
  final String role;
  final String content;
  final int createdAt;

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
    id: map['id'] as int,
    topicId: map['topic_id'] as int,
    role: map['role'] as String,
    content: map['content'] as String,
    createdAt: map['created_at'] as int,
  );
}

class ChatStore {
  ChatStore._();
  static final ChatStore instance = ChatStore._();
  static const _secrets = FlutterSecureStorage();
  Database? _database;

  Future<Database> get db async {
    if (_database != null) return _database!;
    final path = p.join(await getDatabasesPath(), 'model_chat.db');
    _database = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE providers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          protocol TEXT NOT NULL,
          base_url TEXT NOT NULL,
          model TEXT NOT NULL
        )''');
        await db.execute('''CREATE TABLE topics (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          provider_id INTEGER REFERENCES providers(id) ON DELETE SET NULL,
          model TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )''');
        await db.execute('''CREATE TABLE messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )''');
        await db.execute(
          'CREATE INDEX messages_topic ON messages(topic_id, id)',
        );
      },
    );
    return _database!;
  }

  Future<List<ProviderConfig>> providers() async => (await (await db).query(
    'providers',
    orderBy: 'id DESC',
  )).map(ProviderConfig.fromMap).toList();

  Future<int> saveProvider(ProviderConfig config, {String? apiKey}) async {
    final database = await db;
    final id = config.id == 0
        ? await database.insert('providers', config.toMap())
        : config.id;
    if (config.id != 0) {
      await database.update(
        'providers',
        config.toMap(),
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      await _secrets.write(key: 'provider_$id', value: apiKey);
    }
    return id;
  }

  Future<String?> apiKey(int providerId) =>
      _secrets.read(key: 'provider_$providerId');

  Future<void> deleteProvider(int id) async {
    await (await db).delete('providers', where: 'id = ?', whereArgs: [id]);
    await _secrets.delete(key: 'provider_$id');
  }

  Future<List<ChatTopic>> topics() async => (await (await db).query(
    'topics',
    orderBy: 'updated_at DESC, id DESC',
  )).map(ChatTopic.fromMap).toList();

  Future<int> createTopic(ProviderConfig provider) async =>
      (await db).insert('topics', {
        'title': '新对话',
        'provider_id': provider.id,
        'model': provider.model,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  Future<void> updateTopic(
    int id, {
    String? title,
    int? providerId,
    String? model,
  }) async {
    final values = <String, Object?>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'title': ?title,
      'provider_id': ?providerId,
      'model': ?model,
    };
    await (await db).update('topics', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTopic(int id) async =>
      (await db).delete('topics', where: 'id = ?', whereArgs: [id]);

  Future<List<ChatMessage>> messages(int topicId) async =>
      (await (await db).query(
        'messages',
        where: 'topic_id = ?',
        whereArgs: [topicId],
        orderBy: 'id',
      )).map(ChatMessage.fromMap).toList();

  Future<int> addMessage(int topicId, String role, String content) async {
    final database = await db;
    final id = await database.insert('messages', {
      'topic_id': topicId,
      'role': role,
      'content': content,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await updateTopic(topicId);
    return id;
  }
}
