import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/agent/web_reader.dart';
import 'package:mulit_ai_flutter/api/tool_call.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';

typedef AgentToolHandler = Future<Map<String, dynamic>> Function(
  AgentToolExecutor executor,
  AgentTask task,
  Map<String, dynamic> arguments,
  int step,
);

class AgentToolDefinition {
  const AgentToolDefinition({
    required this.description,
    required this.labelKey,
    required this.properties,
    required this.requiredArguments,
    required this.execute,
    this.requiresProject = false,
    this.requiresSearch = false,
  });

  final String description;
  final String labelKey;
  final Map<String, dynamic> properties;
  final List<String> requiredArguments;
  final bool requiresProject;
  final bool requiresSearch;
  final AgentToolHandler execute;

  bool isAvailable({required bool project, required bool search}) =>
      (!requiresProject || project) && (!requiresSearch || search);

  Map<String, dynamic> schema(String name) => {
    'name': name,
    'description': description,
    'parameters': {
      'type': 'object',
      'properties': properties,
      'required': requiredArguments,
      'additionalProperties': false,
    },
  };
}

/// One registration owns the schema, permissions, implementation and display name.
final agentToolRegistry = Map<String, AgentToolDefinition>.unmodifiable({
  'search_web': AgentToolDefinition(
    description: 'Search public web sources. Do not include private project text in queries.',
    labelKey: 'i18n.agent_tool_search',
    properties: const {
      'query': {'type': 'string', 'maxLength': 500},
    },
    requiredArguments: const ['query'],
    requiresSearch: true,
    execute: (executor, task, args, step) =>
        executor._searchWeb(task, args, step),
  ),
  'read_webpage': AgentToolDefinition(
    description: 'Read a public HTTPS page, up to 10000 characters. No login or JavaScript interaction.',
    labelKey: 'i18n.agent_tool_read',
    properties: const {
      'url': {'type': 'string', 'maxLength': 4096},
    },
    requiredArguments: const ['url'],
    execute: (executor, task, args, step) =>
        executor._readWebpage(task, args, step),
  ),
  'search_project': AgentToolDefinition(
    description: 'Find relevant excerpts in the authorized project, returning document IDs and source labels.',
    labelKey: 'i18n.agent_tool_project',
    properties: const {
      'query': {'type': 'string', 'maxLength': 500},
    },
    requiredArguments: const ['query'],
    requiresProject: true,
    execute: (executor, task, args, step) =>
        executor._searchProject(task, args, step),
  ),
  'read_project_document': AgentToolDefinition(
    description: 'Read an authorized project document in pages of up to 8000 characters.',
    labelKey: 'i18n.agent_tool_document',
    properties: const {
      'document_id': {'type': 'integer'},
      'offset': {'type': 'integer', 'minimum': 0},
    },
    requiredArguments: const ['document_id'],
    requiresProject: true,
    execute: (executor, task, args, step) =>
        executor._readProjectDocument(task, args, step),
  ),
  'save_artifact': AgentToolDefinition(
    description: 'Save a real local file. Name must end in .md, .pdf, .docx, .csv or .xlsx. Supply Markdown content for MD/PDF/Word, or valid quoted CSV content for CSV/Excel. No binary, Base64 or raw XML.',
    labelKey: 'i18n.agent_tool_save',
    properties: const {
      'name': {'type': 'string', 'maxLength': 100},
      'content': {'type': 'string', 'maxLength': 40000},
    },
    requiredArguments: const ['name', 'content'],
    execute: (executor, task, args, step) =>
        executor._saveArtifact(task, args, step),
  ),
});

List<Map<String, dynamic>> agentTools({
  required bool project,
  required bool search,
}) => [
  for (final entry in agentToolRegistry.entries)
    if (entry.value.isAvailable(project: project, search: search))
      entry.value.schema(entry.key),
];

String agentToolLabel(String name) =>
    T(agentToolRegistry[name]?.labelKey ?? 'i18n.agent_tool_unknown');

/// Owns cancellable tool resources; the runner owns run budgets and persistence.
class AgentToolExecutor {
  AgentToolExecutor({required this.repository, required this.check});
  final AgentStore repository;
  final void Function() check;
  SearchClient? _search;
  AgentWebReader? _reader;

  void cancel() {
    _search?.cancel();
    _reader?.cancel();
  }

  Future<Map<String, dynamic>> execute(
    AgentTask task,
    ModelToolCall call,
    int step,
  ) async {
    check();
    final tool = agentToolRegistry[call.name];
    final args = call.arguments;
    if (tool == null ||
        call.argumentError ||
        tool.requiresProject && task.projectId == null ||
        args.keys.any((key) => !tool.properties.containsKey(key)) ||
        tool.requiredArguments.any((key) => !args.containsKey(key))) {
      throw const FormatException('Tool');
    }
    if (tool.requiresSearch &&
        await repository.store.setting('search_enabled') != '1') {
      throw const FormatException('Search disabled');
    }
    check();
    return tool.execute(this, task, args, step);
  }

  void _addSource(AgentTask task, Map<String, dynamic> source) {
    final existing = task.sources
        .where(
          (s) => source['url'] != null
              ? s['url'] == source['url']
              : s['label'] == source['label'],
        )
        .firstOrNull;
    if (existing != null) {
      if (source['read'] == true) {
        existing['read'] = true;
        existing['excerpt'] = source['excerpt'];
      }
      return;
    }
    if (task.sources.length >= 40) return;
    task.sources.add(source);
  }

  String _string(Map<String, dynamic> args, String key, int max) {
    final value = args[key];
    if (value is! String || value.trim().isEmpty || value.length > max) {
      throw const FormatException('Argument');
    }
    return value;
  }

  Future<Map<String, dynamic>> _searchWeb(
    AgentTask task,
    Map<String, dynamic> a,
    int step,
  ) async {
    final config = await repository.store.selectedSearchProvider();
    if (config == null) {
      throw const FormatException('Search not configured');
    }
    final key = await repository.store.searchApiKey(config);
    if (key == null || key.isEmpty) {
      throw const FormatException('Search key');
    }
    check();
    final client = SearchClient(config, key);
    _search = client;
    try {
      final result = await client.search(_string(a, 'query', 500));
      check();
      final sources = result.sources
          .map((s) => {'label': s.url, ...s.toJson()})
          .toList();
      for (final source in sources) {
        _addSource(task, source);
      }
      return {'sources': sources};
    } finally {
      client.cancel();
      _search = null;
    }
  }

  Future<Map<String, dynamic>> _readWebpage(
    AgentTask task,
    Map<String, dynamic> a,
    int step,
  ) async {
    final reader = AgentWebReader();
    _reader = reader;
    try {
      final result = await reader.read(_string(a, 'url', 4096));
      check();
      _addSource(task, {
        'label': result['url'],
        'title': result['url'],
        'url': result['url'],
        'excerpt': result['text'],
        'read': true,
      });
      return result;
    } finally {
      reader.cancel();
      _reader = null;
    }
  }

  Future<Map<String, dynamic>> _searchProject(
    AgentTask task,
    Map<String, dynamic> a,
    int step,
  ) async {
    final project = await repository.store.project(task.projectId);
    if (project == null) {
      throw const FormatException('Project not authorized');
    }
    final sources = await repository.store.retrieveKnowledge(
      project.id,
      _string(a, 'query', 500),
    );
    check();
    for (final source in sources) {
      _addSource(task, {
        'documentId': source.documentId,
        'chunk': source.chunk,
        'label': source.label,
        'title': source.name,
        'excerpt': source.text,
      });
    }
    return {
      'sources': sources.map((s) => {...s.toJson(), 'label': s.label}).toList(),
    };
  }

  Future<Map<String, dynamic>> _readProjectDocument(
    AgentTask task,
    Map<String, dynamic> a,
    int step,
  ) async {
    final id = a['document_id'];
    final offset = a['offset'] ?? 0;
    if (task.projectId == null || id is! int || offset is! int || offset < 0) {
      throw const FormatException('Document');
    }
    final rows = await (await repository.store.db).query(
      'knowledge_documents',
      columns: ['name', 'content'],
      where: 'id = ? AND project_id = ?',
      whereArgs: [id, task.projectId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const FormatException('Document not authorized');
    }
    final content = rows.single['content'] as String;
    if (offset > content.length) throw const FormatException('Offset');
    final text = content.substring(
      offset,
      (offset + 8000).clamp(0, content.length),
    );
    final label = 'D$id@$offset';
    check();
    _addSource(task, {
      'documentId': id,
      'label': label,
      'title': rows.single['name'],
      'excerpt': text,
    });
    return {
      'label': label,
      'name': rows.single['name'],
      'text': text,
      'next_offset': offset + text.length < content.length
          ? offset + text.length
          : null,
    };
  }

  Future<Map<String, dynamic>> _saveArtifact(
    AgentTask task,
    Map<String, dynamic> a,
    int step,
  ) async {
    final artifact = await repository.writeArtifact(
      task,
      '$step',
      _string(a, 'name', 100),
      _string(a, 'content', 40000),
    );
    return {'saved': artifact['name']};
  }
}
