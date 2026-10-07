import 'dart:convert';
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:mulit_ai_flutter/search/search_service.dart';

class KeychainAccessException implements Exception {
  const KeychainAccessException();

  @override
  String toString() =>
      '无法访问 macOS 钥匙串。请解锁登录钥匙串，并在系统授权弹窗中允许 AI Link 访问密钥。若曾拒绝，请重新打开应用后再试，或重新填写并保存密钥。';
}

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
    this.id,
    this.name,
    this.baseUrl,
    this.model,
    this.protocol,
  );
  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final ApiProtocol protocol;
  String get iconAsset => 'assets/provider_icons/$id.svg';
}

const providerPresets = <ProviderPreset>[
  ProviderPreset(
    'openai',
    'OpenAI',
    'https://api.openai.com/v1',
    'gpt-4.1-mini',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'claude',
    'Claude',
    'https://api.anthropic.com/v1',
    'claude-sonnet-5',
    ApiProtocol.anthropic,
  ),
  ProviderPreset(
    'gemini',
    'Gemini',
    'https://generativelanguage.googleapis.com/v1beta/openai',
    'gemini-3.8-flash',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'deepseek',
    'DeepSeek',
    'https://api.deepseek.com',
    'deepseek-flash',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'glm',
    'GLM 智谱',
    'https://open.bigmodel.cn/api/paas/v4',
    'glm-4.5',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'qwen',
    '千问 Qwen',
    'https://dashscope.aliyuncs.com/compatible-mode/v1',
    'qwen-plus',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'doubao',
    '豆包 / 火山方舟',
    'https://ark.cn-beijing.volces.com/api/v3',
    'doubao-seed-2-1-pro-260628',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'baidu',
    '百度千帆 / 文心',
    'https://qianfan.baidubce.com/v2',
    'ernie-5.0',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'hunyuan',
    '腾讯混元 TokenHub',
    'https://tokenhub.tencentmaas.com/v1',
    'hy3',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'moonshot',
    'Kimi / Moonshot',
    'https://api.moonshot.cn/v1',
    'kimi-k2.5',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'minimax',
    'MiniMax',
    'https://api.minimaxi.com/v1',
    'MiniMax-M3',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'siliconflow',
    '硅基流动',
    'https://api.siliconflow.cn/v1',
    'deepseek-ai/DeepSeek-V4-Flash',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'openrouter',
    'OpenRouter',
    'https://openrouter.ai/api/v1',
    '~openai/gpt-latest',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'grok',
    'xAI / Grok',
    'https://api.x.ai/v1',
    'latest',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'groq',
    'Groq',
    'https://api.groq.com/openai/v1',
    'llama-3.3-70b-versatile',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'mistral',
    'Mistral AI',
    'https://api.mistral.ai/v1',
    'mistral-small-latest',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'perplexity',
    'Perplexity',
    'https://api.perplexity.ai',
    'sonar',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'together',
    'Together AI',
    'https://api.together.ai/v1',
    'MiniMaxAI/MiniMax-M3',
    ApiProtocol.openAi,
  ),
  ProviderPreset(
    'fireworks',
    'Fireworks AI',
    'https://api.fireworks.ai/inference/v1',
    'accounts/fireworks/models/glm-5p3-flash',
    ApiProtocol.openAi,
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

String validateScannedApiKey(String input) {
  final key = input.trim();
  if (key.isEmpty || key.contains(RegExp(r'[\x00-\x1F]'))) {
    throw const FormatException('二维码中没有有效的 API Key');
  }
  if (key.startsWith('{') && key.endsWith('}')) {
    throw const FormatException('请扫描仅包含 API Key 字符串的二维码');
  }
  return key;
}

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.protocol,
    this.presetId,
  });
  final int id;
  final String name;
  final String baseUrl;
  final String model;
  final ApiProtocol protocol;
  final String? presetId;

  ProviderConfig copyWith({
    int? id,
    String? name,
    String? baseUrl,
    String? model,
    ApiProtocol? protocol,
    String? presetId,
  }) => ProviderConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    protocol: protocol ?? this.protocol,
    presetId: presetId ?? this.presetId,
  );

  Map<String, Object?> toMap() => {
    'name': name,
    'base_url': baseUrl,
    'model': model,
    'protocol': protocol.value,
    'preset_id': presetId,
  };

  Map<String, Object?> toImportJson() => {
    'name': name,
    'protocol': protocol.value,
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': '',
    if (presetId != null) 'presetId': presetId,
  };

  factory ProviderConfig.fromMap(Map<String, Object?> map) => ProviderConfig(
    id: map['id'] as int,
    name: map['name'] as String,
    baseUrl: map['base_url'] as String,
    model: map['model'] as String,
    protocol: ApiProtocol.parse(map['protocol'] as String),
    presetId: map['preset_id'] as String?,
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
        presetId: providerPresets.any((p) => p.id == decoded['presetId'])
            ? decoded['presetId'] as String
            : null,
      ),
      key: key,
    );
  }

  static ({ProviderConfig config, String key}) fromQrCode(String source) {
    late final ({ProviderConfig config, String key}) value;
    try {
      value = fromImportJson(source);
    } on FormatException catch (error) {
      throw FormatException(error.message);
    } catch (_) {
      throw const FormatException('二维码配置字段格式不正确');
    }
    if (value.key.isEmpty) {
      throw const FormatException('二维码缺少 API Key');
    }
    return value;
  }
}

ProviderPreset? presetForProvider(ProviderConfig config) {
  for (final preset in providerPresets) {
    if (preset.id == config.presetId ||
        (config.presetId == null &&
            preset.baseUrl == config.baseUrl &&
            preset.name == config.name)) {
      return preset;
    }
  }
  return null;
}

String composeSystemPrompt(String globalPrompt, String modelPrompt) => [
  globalPrompt.trim(),
  modelPrompt.trim(),
].where((part) => part.isNotEmpty).join('\n\n');

class ModelPrompt {
  const ModelPrompt({
    required this.providerId,
    required this.model,
    required this.prompt,
  });
  final int providerId;
  final String model;
  final String prompt;

  factory ModelPrompt.fromMap(Map<String, Object?> map) => ModelPrompt(
    providerId: map['provider_id'] as int,
    model: map['model'] as String,
    prompt: map['prompt'] as String,
  );
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

class ChatSelection {
  const ChatSelection(this.providerId, this.model);

  final int providerId;
  final String model;

  String toJson() => jsonEncode({'providerId': providerId, 'model': model});

  static ChatSelection? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final providerId = value['providerId'];
      final model = value['model'];
      if (providerId is! int || model is! String || model.trim().isEmpty) {
        return null;
      }
      return ChatSelection(providerId, model);
    } catch (_) {
      return null;
    }
  }
}

/// Phone model changes and explicit watch model choices update the same
/// selection. Before the first update, prefer the phone's current selection
/// over the separate watch settings left by older app versions.
Future<ChatSelection?> loadWatchChatSelection(ChatStore store) async {
  final selection = ChatSelection.tryParse(
    await store.setting('watch_chat_selection'),
  );
  if (selection != null) return selection;
  final phone = ChatSelection.tryParse(
    await store.setting('last_chat_selection'),
  );
  if (phone != null) return phone;
  final providerId = int.tryParse(
    await store.setting('watch_provider_id') ?? '',
  );
  final model = await store.setting('watch_model_id');
  if (providerId == null || model == null || model.trim().isEmpty) return null;
  return ChatSelection(providerId, model);
}

ChatSelection? initialChatSelection(
  List<ProviderConfig> providers,
  List<ChatTopic> topics,
  ChatSelection? saved,
) {
  if (providers.isEmpty) return null;
  if (saved != null &&
      providers.any((provider) => provider.id == saved.providerId)) {
    return saved;
  }
  for (final topic in topics) {
    if (topic.providerId != null &&
        topic.model.trim().isNotEmpty &&
        providers.any((provider) => provider.id == topic.providerId)) {
      return ChatSelection(topic.providerId!, topic.model);
    }
  }
  final provider = providers.first;
  return ChatSelection(provider.id, provider.model);
}

String initialTopicTitle(String content) {
  final compact = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  return compact.length > 28 ? '${compact.substring(0, 28)}…' : compact;
}

String? normalizeGeneratedTopicTitle(String raw) {
  final firstLine = raw
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .firstOrNull;
  if (firstLine == null) return null;
  final compact = firstLine
      .replaceFirst(RegExp(r'^(标题|Title)\s*[:：]\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^[#*"“”「」]+|[#*"“”「」]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (compact.isEmpty) return null;
  return compact.length > 28 ? '${compact.substring(0, 28)}…' : compact;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.topicId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.providerId,
    this.providerName,
    this.providerPresetId,
    this.modelId,
    this.firstTokenMs,
    this.totalMs,
    this.inputTokens,
    this.outputTokens,
    this.searchSources = const [],
  });
  final int id;
  final int topicId;
  final String role;
  final String content;
  final int createdAt;
  final int? providerId;
  final String? providerName;
  final String? providerPresetId;
  final String? modelId;
  final int? firstTokenMs;
  final int? totalMs;
  final int? inputTokens;
  final int? outputTokens;
  final List<SearchSource> searchSources;

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
    id: map['id'] as int,
    topicId: map['topic_id'] as int,
    role: map['role'] as String,
    content: map['content'] as String,
    createdAt: map['created_at'] as int,
    providerId: map['provider_id'] as int?,
    providerName: map['provider_name'] as String?,
    providerPresetId: map['provider_preset_id'] as String?,
    modelId: map['model_id'] as String?,
    firstTokenMs: map['first_token_ms'] as int?,
    totalMs: map['total_ms'] as int?,
    inputTokens: map['input_tokens'] as int?,
    outputTokens: map['output_tokens'] as int?,
    searchSources: SearchSource.decode(map['search_sources'] as String?),
  );
}

class CachedModelList {
  const CachedModelList({
    required this.baseUrl,
    required this.protocol,
    required this.models,
    required this.fetchedAt,
  });

  final String baseUrl;
  final ApiProtocol protocol;
  final List<String> models;
  final DateTime fetchedAt;

  bool matches(ProviderConfig provider) =>
      baseUrl == provider.baseUrl && protocol == provider.protocol;

  String toJson() => jsonEncode({
    'baseUrl': baseUrl,
    'protocol': protocol.value,
    'models': models,
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
  });

  static CachedModelList? tryParse(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['baseUrl'] is! String ||
          value['protocol'] is! String ||
          value['models'] is! List ||
          value['fetchedAt'] is! int) {
        return null;
      }
      final models = value['models'] as List;
      if (models.isEmpty || models.any((model) => model is! String)) {
        return null;
      }
      return CachedModelList(
        baseUrl: value['baseUrl'] as String,
        protocol: ApiProtocol.parse(value['protocol'] as String),
        models: models.cast<String>(),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(
          value['fetchedAt'] as int,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

enum VoiceProtocol { openAi, mimo, doubao }

class VoiceProviderConfig {
  const VoiceProviderConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.asrModel,
    required this.ttsModel,
    required this.voice,
    this.textProviderId,
  });

  final String id;
  final String name;
  final VoiceProtocol protocol;
  final String baseUrl;
  final String asrModel;
  final String ttsModel;
  final String voice;
  final int? textProviderId;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'baseUrl': baseUrl,
    'asrModel': asrModel,
    'ttsModel': ttsModel,
    'voice': voice,
    'textProviderId': textProviderId,
  };

  factory VoiceProviderConfig.fromJson(Map<String, dynamic> json) =>
      VoiceProviderConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        protocol: VoiceProtocol.values.byName(json['protocol'] as String),
        baseUrl: json['baseUrl'] as String,
        asrModel: json['asrModel'] as String,
        ttsModel: json['ttsModel'] as String,
        voice: json['voice'] as String,
        textProviderId: json['textProviderId'] as int?,
      );
}

class ChatStore {
  ChatStore._();
  static final ChatStore instance = ChatStore._();
  final _watchConfigurationChanges = StreamController<void>.broadcast();
  Stream<void> get watchConfigurationChanges =>
      _watchConfigurationChanges.stream;
  // This app does not share Keychain items with other apps. The macOS login
  // Keychain works without a Keychain Sharing provisioning profile.
  static const _secrets = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  Database? _database;

  Future<T> _withSecureStorage<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PlatformException {
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        throw const KeychainAccessException();
      }
      rethrow;
    }
  }

  Future<Database> get db async {
    if (_database != null) return _database!;
    final path = p.join(await getDatabasesPath(), 'model_chat.db');
    _database = await openDatabase(
      path,
      version: 5,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE providers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          protocol TEXT NOT NULL,
          base_url TEXT NOT NULL,
          model TEXT NOT NULL,
          preset_id TEXT
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
          created_at INTEGER NOT NULL,
          provider_id INTEGER,
          provider_name TEXT,
          provider_preset_id TEXT,
          model_id TEXT,
          first_token_ms INTEGER,
          total_ms INTEGER,
          input_tokens INTEGER,
          output_tokens INTEGER,
          search_sources TEXT
        )''');
        await db.execute(
          'CREATE INDEX messages_topic ON messages(topic_id, id)',
        );
        await _createPromptTables(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE providers ADD COLUMN preset_id TEXT');
          await _createPromptTables(db);
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE messages ADD COLUMN model_id TEXT');
          await db.execute(
            'ALTER TABLE messages ADD COLUMN first_token_ms INTEGER',
          );
          await db.execute('ALTER TABLE messages ADD COLUMN total_ms INTEGER');
          await db.execute(
            'ALTER TABLE messages ADD COLUMN input_tokens INTEGER',
          );
          await db.execute(
            'ALTER TABLE messages ADD COLUMN output_tokens INTEGER',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE messages ADD COLUMN provider_id INTEGER',
          );
          await db.execute(
            'ALTER TABLE messages ADD COLUMN provider_name TEXT',
          );
          await db.execute(
            'ALTER TABLE messages ADD COLUMN provider_preset_id TEXT',
          );
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE messages ADD COLUMN search_sources TEXT',
          );
        }
      },
    );
    return _database!;
  }

  static Future<void> _createPromptTables(Database db) async {
    await db.execute('''CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE model_prompts (
      provider_id INTEGER NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
      model TEXT NOT NULL,
      prompt TEXT NOT NULL,
      PRIMARY KEY(provider_id, model)
    )''');
  }

  Future<List<ProviderConfig>> providers() async => (await (await db).query(
    'providers',
    orderBy: 'id DESC',
  )).map(ProviderConfig.fromMap).toList();

  Future<int> saveProvider(ProviderConfig config, {String? apiKey}) async {
    final database = await db;
    if (config.id != 0 &&
        (apiKey?.isNotEmpty == true || await cachedModels(config) == null)) {
      await deleteModelCache(config.id);
    }
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
      await _withSecureStorage(
        () => _secrets.write(key: 'provider_$id', value: apiKey),
      );
    }
    return id;
  }

  Future<String?> apiKey(int providerId) =>
      _withSecureStorage(() => _secrets.read(key: 'provider_$providerId'));

  Future<List<SearchProviderConfig>> searchProviders() async {
    final raw = await setting('search_providers');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map(
          (item) => SearchProviderConfig.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<SearchProviderConfig?> selectedSearchProvider() async {
    final id = await setting('search_provider_id');
    return (await searchProviders()).where((item) => item.id == id).firstOrNull;
  }

  Future<String?> searchApiKey(String id) =>
      _withSecureStorage(() => _secrets.read(key: 'search_$id'));

  Future<void> saveSearchProvider(
    SearchProviderConfig config, {
    String? apiKey,
  }) async {
    final previous = (await searchProviders())
        .where((item) => item.id == config.id)
        .firstOrNull;
    final key = apiKey?.trim() ?? '';
    if (config.name.trim().isEmpty ||
        config.id.isEmpty ||
        config.maxResults < 1 ||
        config.maxResults > 10) {
      throw const FormatException('请填写服务名称，搜索结果数量须为 1 至 10');
    }
    validateBaseUrl(config.endpoint);
    if (key.isEmpty &&
        (previous == null ||
            previous.service != config.service ||
            previous.endpoint != config.endpoint ||
            (await searchApiKey(config.id))?.isNotEmpty != true)) {
      throw const FormatException('请填写搜索服务 API Key；更换服务类型或地址时须重新填写。');
    }
    if (key.contains(RegExp(r'[\x00-\x1F]'))) {
      throw const FormatException('API Key 不能包含换行或控制字符');
    }
    if (key.isNotEmpty) {
      await _withSecureStorage(
        () => _secrets.write(key: 'search_${config.id}', value: key),
      );
    }
    final database = await db;
    await database.transaction((txn) async {
      final rows = await txn.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['search_providers'],
      );
      final items = rows.isEmpty
          ? <SearchProviderConfig>[]
          : (jsonDecode(rows.single['value'] as String) as List)
                .map(
                  (item) => SearchProviderConfig.fromJson(
                    item as Map<String, dynamic>,
                  ),
                )
                .toList();
      items.removeWhere((item) => item.id == config.id);
      items.add(config);
      await txn.insert('settings', {
        'key': 'search_providers',
        'value': jsonEncode(items.map((item) => item.toJson()).toList()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final selected = await txn.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['search_provider_id'],
      );
      if (selected.isEmpty || (selected.single['value'] as String).isEmpty) {
        await txn.insert('settings', {
          'key': 'search_provider_id',
          'value': config.id,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _watchConfigurationChanges.add(null);
  }

  Future<void> deleteSearchProvider(String id) async {
    await (await db).transaction((txn) async {
      final rows = await txn.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['search_providers'],
      );
      final items = rows.isEmpty
          ? <SearchProviderConfig>[]
          : (jsonDecode(rows.single['value'] as String) as List)
                .map(
                  (item) => SearchProviderConfig.fromJson(
                    item as Map<String, dynamic>,
                  ),
                )
                .toList();
      items.removeWhere((item) => item.id == id);
      await txn.insert('settings', {
        'key': 'search_providers',
        'value': jsonEncode(items.map((item) => item.toJson()).toList()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final selected = await txn.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['search_provider_id'],
      );
      if (selected.isNotEmpty && selected.single['value'] == id) {
        for (final key in ['search_provider_id', 'search_enabled']) {
          await txn.insert('settings', {
            'key': key,
            'value': key == 'search_enabled' ? '0' : '',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
    await _withSecureStorage(() => _secrets.delete(key: 'search_$id'));
    _watchConfigurationChanges.add(null);
  }

  Future<List<VoiceProviderConfig>> voiceProviders() async {
    final raw = await setting('voice_providers');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map(
            (item) =>
                VoiceProviderConfig.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveVoiceProvider(
    VoiceProviderConfig config, {
    String? apiKey,
  }) async {
    final items = await voiceProviders();
    items.removeWhere((item) => item.id == config.id);
    items.add(config);
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await _withSecureStorage(
        () => _secrets.write(key: 'voice_${config.id}', value: apiKey.trim()),
      );
    } else if (config.textProviderId != null) {
      await _withSecureStorage(
        () => _secrets.delete(key: 'voice_${config.id}'),
      );
    }
    await saveSetting(
      'voice_providers',
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<String?> voiceApiKey(VoiceProviderConfig config) async {
    if (config.textProviderId case final id?) return apiKey(id);
    return _withSecureStorage(() => _secrets.read(key: 'voice_${config.id}'));
  }

  Future<void> deleteVoiceProvider(String id) async {
    final items = await voiceProviders();
    items.removeWhere((item) => item.id == id);
    await saveSetting(
      'voice_providers',
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    await _withSecureStorage(() => _secrets.delete(key: 'voice_$id'));
    if (await setting('voice_asr_id') == id) {
      await saveSetting('voice_asr_id', '');
    }
    if (await setting('voice_tts_id') == id) {
      await saveSetting('voice_tts_id', '');
    }
  }

  Future<void> deleteProvider(int id) async {
    for (final voice in await voiceProviders()) {
      if (voice.textProviderId == id) await deleteVoiceProvider(voice.id);
    }
    await (await db).delete('providers', where: 'id = ?', whereArgs: [id]);
    await deleteModelCache(id);
    if ((await lastChatSelection())?.providerId == id) {
      await (await db).delete(
        'settings',
        where: 'key = ?',
        whereArgs: ['last_chat_selection'],
      );
    }
    await _withSecureStorage(() => _secrets.delete(key: 'provider_$id'));
  }

  /// Clears app-owned local data after explicit confirmation in the UI.
  Future<void> clearAllData() async {
    await (await db).transaction((transaction) async {
      await transaction.delete('messages');
      await transaction.delete('topics');
      await transaction.delete('model_prompts');
      await transaction.delete('settings');
      await transaction.delete('providers');
    });
    await _withSecureStorage(() => _secrets.deleteAll());
  }

  Future<String> globalPrompt() async {
    return await setting('global_prompt') ?? '';
  }

  Future<String?> setting(String key) async {
    final rows = await (await db).query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> saveSetting(String key, String value) async {
    await (await db).insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (key == 'search_enabled' || key == 'search_provider_id') {
      _watchConfigurationChanges.add(null);
    }
  }

  Future<ChatSelection?> lastChatSelection() async =>
      ChatSelection.tryParse(await setting('last_chat_selection'));

  Future<void> saveLastChatSelection(ChatSelection selection) async {
    // A background watch worker must never see a new provider with an old model.
    await (await db).transaction((txn) async {
      for (final key in ['last_chat_selection', 'watch_chat_selection']) {
        await txn.insert('settings', {
          'key': key,
          'value': selection.toJson(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> saveWatchChatSelection(ChatSelection selection) async {
    await (await db).transaction((txn) async {
      await txn.insert('settings', {
        'key': 'watch_chat_selection',
        'value': selection.toJson(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('settings', {
        'key': 'watch_topic_id',
        'value': '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  static String _modelCacheKey(int providerId) => 'model_cache_$providerId';

  Future<CachedModelList?> cachedModels(ProviderConfig provider) async {
    if (provider.id == 0) return null;
    final raw = await setting(_modelCacheKey(provider.id));
    final cached = raw == null ? null : CachedModelList.tryParse(raw);
    return cached?.matches(provider) == true ? cached : null;
  }

  Future<void> saveModelCache(
    ProviderConfig provider,
    List<String> models,
  ) async {
    if (provider.id == 0) return;
    final normalized =
        models.where((model) => model.trim().isNotEmpty).toSet().toList()
          ..sort();
    if (normalized.isEmpty) return;
    await saveSetting(
      _modelCacheKey(provider.id),
      CachedModelList(
        baseUrl: provider.baseUrl,
        protocol: provider.protocol,
        models: normalized,
        fetchedAt: DateTime.now(),
      ).toJson(),
    );
  }

  Future<void> deleteModelCache(int providerId) async {
    await (await db).delete(
      'settings',
      where: 'key = ?',
      whereArgs: [_modelCacheKey(providerId)],
    );
  }

  Future<void> saveGlobalPrompt(String prompt) async {
    await saveSetting('global_prompt', prompt.trim());
  }

  Future<List<ModelPrompt>> modelPrompts() async => (await (await db).query(
    'model_prompts',
    orderBy: 'provider_id, model',
  )).map(ModelPrompt.fromMap).toList();

  Future<void> saveModelPrompt(
    int providerId,
    String model,
    String prompt,
  ) async {
    final database = await db;
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) throw const FormatException('请输入模型 ID');
    if (prompt.trim().isEmpty) {
      await deleteModelPrompt(providerId, normalizedModel);
      return;
    }
    await database.insert('model_prompts', {
      'provider_id': providerId,
      'model': normalizedModel,
      'prompt': prompt.trim(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteModelPrompt(int providerId, String model) async =>
      (await db).delete(
        'model_prompts',
        where: 'provider_id = ? AND model = ?',
        whereArgs: [providerId, model],
      );

  Future<String> systemPrompt(int providerId, String model) async {
    final global = await globalPrompt();
    final rows = await (await db).query(
      'model_prompts',
      columns: ['prompt'],
      where: 'provider_id = ? AND model = ?',
      whereArgs: [providerId, model],
      limit: 1,
    );
    return composeSystemPrompt(
      global,
      rows.isEmpty ? '' : rows.first['prompt'] as String,
    );
  }

  Future<List<ChatTopic>> topics() async => (await (await db).query(
    'topics',
    orderBy: 'updated_at DESC, id DESC',
  )).map(ChatTopic.fromMap).toList();

  /// Topic IDs that have received at least one watch turn. The mapping is
  /// already persisted for idempotent watch sync, including older phone relays.
  Future<Set<int>> watchTopicIds() async {
    final rows = await (await db).query(
      'settings',
      columns: ['value'],
      where: "key = 'watch_topic_id' OR key LIKE 'watch_conversation_%'",
    );
    return rows
        .map((row) => int.tryParse(row['value'] as String))
        .whereType<int>()
        .toSet();
  }

  Future<int> createTopicWithMessage(
    ProviderConfig provider,
    String model,
    String content,
  ) async {
    final title = initialTopicTitle(content);
    final now = DateTime.now().millisecondsSinceEpoch;
    return (await db).transaction((transaction) async {
      final topicId = await transaction.insert('topics', {
        'title': title,
        'provider_id': provider.id,
        'model': model,
        'updated_at': now,
      });
      await transaction.insert('messages', {
        'topic_id': topicId,
        'role': 'user',
        'content': content,
        'created_at': now,
        'provider_id': provider.id,
        'provider_name': provider.name,
        'provider_preset_id': presetForProvider(provider)?.id,
        'model_id': model,
      });
      return topicId;
    });
  }

  /// Applies a watch turn once, in conversation order, when the phone reconnects.
  Future<void> saveWatchTurn(Map<String, dynamic> turn) async {
    final id = turn['id'];
    final conversationId = turn['conversationId'];
    final sequence = turn['sequence'];
    final transcript = turn['transcript'];
    final answer = turn['answer'];
    final model = turn['model'];
    final providerName = turn['providerName'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9-]{36}$').hasMatch(id) ||
        conversationId is! String ||
        !RegExp(r'^[a-f0-9-]{36}$').hasMatch(conversationId) ||
        sequence is! int ||
        sequence < 0 ||
        transcript is! String ||
        transcript.trim().isEmpty ||
        transcript.length > 10000 ||
        answer is! String ||
        answer.isEmpty ||
        answer.length > 100000 ||
        model is! String ||
        model.isEmpty ||
        model.length > 500 ||
        providerName is! String ||
        providerName.length > 200) {
      throw const FormatException('手表会话数据无效');
    }
    final providerId = turn['providerId'] is int
        ? turn['providerId'] as int
        : null;
    final when = turn['createdAt'] is int
        ? turn['createdAt'] as int
        : DateTime.now().millisecondsSinceEpoch;
    final database = await db;
    await database.transaction((transaction) async {
      Future<String?> value(String key) async {
        final rows = await transaction.query(
          'settings',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: [key],
          limit: 1,
        );
        return rows.isEmpty ? null : rows.first['value'] as String;
      }

      Future<void> put(String key, String value) => transaction
          .insert('settings', {
            'key': key,
            'value': value,
          }, conflictAlgorithm: ConflictAlgorithm.replace)
          .then((_) {});
      if (await value('watch_turn_$id') != null) return;
      final sequenceKey = 'watch_sequence_$conversationId';
      final expected = int.tryParse(await value(sequenceKey) ?? '0') ?? 0;
      final topicKey = 'watch_conversation_$conversationId';
      final existingTopicId = int.tryParse(await value(topicKey) ?? '');
      // Apple Watch sends only the oldest unacknowledged turn. After phone data
      // is cleared, its first pending turn can start a restored conversation.
      // Existing conversations and the Wear OS protocol retain strict ordering.
      final restoresMissingAppleConversation =
          turn['source'] == 'apple-watch' &&
          expected == 0 &&
          existingTopicId == null &&
          sequence > 0;
      if (sequence != expected && !restoresMissingAppleConversation) {
        throw StateError('等待前一条手表会话同步');
      }
      final existingTopic = existingTopicId == null
          ? <Map<String, Object?>>[]
          : await transaction.query(
              'topics',
              where: 'id = ?',
              whereArgs: [existingTopicId],
            );
      final validProvider = providerId == null
          ? <Map<String, Object?>>[]
          : await transaction.query(
              'providers',
              columns: ['id'],
              where: 'id = ?',
              whereArgs: [providerId],
            );
      final storedProviderId = validProvider.isEmpty ? null : providerId;
      final topicId = existingTopic.isNotEmpty
          ? existingTopicId!
          : await transaction.insert('topics', {
              'title': initialTopicTitle(transcript),
              'provider_id': storedProviderId,
              'model': model,
              'updated_at': when,
            });
      final common = <String, Object?>{
        'topic_id': topicId,
        'provider_id': storedProviderId,
        'provider_name': providerName,
        'provider_preset_id': turn['providerPresetId'] is String
            ? turn['providerPresetId'] as String
            : null,
        'model_id': model,
        'created_at': when,
      };
      await transaction.insert('messages', {
        ...common,
        'role': 'user',
        'content': transcript,
      });
      await transaction.insert('messages', {
        ...common,
        'role': 'assistant',
        'content': answer,
      });
      await transaction.update(
        'topics',
        {'updated_at': when},
        where: 'id = ?',
        whereArgs: [topicId],
      );
      await put(topicKey, '$topicId');
      await put(sequenceKey, '${sequence + 1}');
      await put('watch_turn_$id', '1');
    });
  }

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

  Future<bool> updateTopicTitleIfUnchanged(
    int id,
    String expectedTitle,
    String title,
  ) async {
    final count = await (await db).update(
      'topics',
      {'title': title},
      where: 'id = ? AND title = ?',
      whereArgs: [id, expectedTitle],
    );
    return count == 1;
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

  Future<int> addMessage(
    int topicId,
    String role,
    String content, {
    String? modelId,
    ProviderConfig? provider,
    int? firstTokenMs,
    int? totalMs,
    int? inputTokens,
    int? outputTokens,
    List<SearchSource> searchSources = const [],
  }) async {
    final database = await db;
    final id = await database.insert('messages', {
      'topic_id': topicId,
      'role': role,
      'content': content,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'provider_id': provider?.id,
      'provider_name': provider?.name,
      'provider_preset_id': provider == null
          ? null
          : presetForProvider(provider)?.id,
      'model_id': modelId,
      'first_token_ms': firstTokenMs,
      'total_ms': totalMs,
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'search_sources': searchSources.isEmpty
          ? null
          : jsonEncode(searchSources.map((source) => source.toJson()).toList()),
    });
    await updateTopic(topicId);
    return id;
  }
}
