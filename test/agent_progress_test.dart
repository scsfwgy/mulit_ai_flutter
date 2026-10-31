import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/agent/agent_progress.dart';
import 'package:mulit_ai_flutter/agent/agent_presentation.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/chat/widgets/message_bubble.dart';
import 'package:mulit_ai_flutter/chat/chat_loading_status.dart';
import 'package:mulit_ai_flutter/chat/chat_message_meta.dart';
import 'package:mulit_ai_flutter/chat/assistant_markdown.dart';

AgentTask task() => AgentTask(
  providerId: 1,
  model: 'test',
  protocol: ApiProtocol.openAi,
  goal: 'Report',
  systemPrompt: '',
)..status = 'running';

Widget progress(
  AgentTask task, {
  bool running = true,
  ValueNotifier<int>? elapsed,
}) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: AgentProgress(
        task: task,
        running: running,
        elapsedMilliseconds: elapsed,
      ),
    ),
  ),
);

void main() {
  test('progress summaries use safe subjects and actual results, never raw arguments', () {
    expect(
      agentStepDetail({
        'name': 'read_webpage',
        'arguments': {'url': 'https://example.com/private/path?token=secret'},
        'status': 'completed',
        'result': {'text': '中文abc'},
      }),
      'example.com · ${F('i18n.agent_extracted_chars', [5])}',
    );
    expect(
      agentStepDetail({
        'name': 'save_artifact',
        'arguments': {'name': '报告.pdf', 'content': 'private document contents'},
      }),
      '报告.pdf',
    );
    expect(
      agentStepDetail({
        'name': 'unknown',
        'arguments': {'api_key': 'secret'},
      }),
      isNull,
    );
    expect(
      agentStepDetail({
        'name': 'search_web',
        'arguments': {'query': 'query'},
        'status': 'completed',
        'result': {
          'sources': [1, 2],
        },
      }),
      'query · ${F('i18n.agent_found_sources', [2])}',
    );
    expect(
      agentStepDetail({
        'name': 'search_web',
        'arguments': {'query': 'query'},
        'status': 'failed',
        'result': {
          'sources': [1, 2],
        },
      }),
      'query',
    );
    expect(
      agentStepDetail({
        'name': 'search_project',
        'arguments': {'query': '中' * 200},
      })!.runes.length,
      141,
    );
  });

  testWidgets(
    'Agent public text stays in progress without a second loading line or final metadata',
    (tester) async {
      final elapsed = ValueNotifier(1200);
      addTearDown(elapsed.dispose);
      Future<void> mount({required bool showLoading}) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              role: 'assistant',
              content: 'Public update',
              loading: true,
              showLoadingStatus: showLoading,
              replyElapsedMs: elapsed,
              searching: false,
              contextTrimmed: false,
              speechState: SpeechPlaybackState.idle,
              speechEnabled: false,
              onCopy: () {},
              onOpenLink: (_) {},
            ),
          ),
        ),
      );
      await mount(showLoading: false);
      expect(find.byType(AssistantMarkdown), findsOneWidget);
      expect(find.byType(ChatLoadingStatus), findsNothing);
      expect(find.byType(ChatMessageMeta), findsNothing);
      await mount(showLoading: true);
      expect(find.byType(ChatLoadingStatus), findsOneWidget);
      expect(find.byType(ChatMessageMeta), findsNothing);
    },
  );

  testWidgets(
    'model waiting advances elapsed time without inventing tool activity',
    (tester) async {
      final t = task()
        ..requests.add({
          'status': 'running',
          'round': 1,
          'tools_enabled': true,
        });
      final elapsed = ValueNotifier(1200);
      addTearDown(elapsed.dispose);
      await tester.pumpWidget(progress(t, elapsed: elapsed));
      expect(
        find.text(
          F('i18n.agent_round_activity', [1, T('i18n.agent_waiting_model')]),
        ),
        findsOneWidget,
      );
      expect(find.text(T('i18n.agent_waiting_steps')), findsOneWidget);
      expect(find.text(F('i18n.agent_elapsed', ['1s 200ms'])), findsOneWidget);
      expect(find.textContaining(T('i18n.agent_tool_search')), findsNothing);
      elapsed.value = 5000;
      await tester.pump();
      expect(find.text(F('i18n.agent_elapsed', ['5s 000ms'])), findsOneWidget);
      expect(t.requests, hasLength(1));
      expect(t.steps, isEmpty);
    },
  );

  testWidgets(
    'tool state and next model round update; completion collapses history',
    (tester) async {
      final t = task()..requests.add({'status': 'completed', 'round': 1});
      t.steps.add({
        'name': 'search_web',
        'status': 'running',
        'arguments': {'query': '五代十国'},
      });
      t.pending.add({'name': 'search_web', 'step': 0});
      await tester.pumpWidget(progress(t));
      expect(
        find.text(
          '${T('i18n.agent_tool_search')} · ${T('i18n.agent_running')}',
        ),
        findsOneWidget,
      );
      expect(find.text('五代十国'), findsOneWidget);
      t.steps.single.addAll({
        'status': 'completed',
        'result': {
          'sources': [1, 2, 3],
        },
      });
      t.pending.clear();
      t.requests.add({'status': 'running', 'round': 2, 'tools_enabled': true});
      await tester.pumpWidget(progress(t));
      expect(
        find.text('五代十国 · ${F('i18n.agent_found_sources', [3])}'),
        findsOneWidget,
      );
      expect(
        find.text(
          F('i18n.agent_round_activity', [2, T('i18n.agent_waiting_model')]),
        ),
        findsOneWidget,
      );
      t.status = 'completed';
      await tester.pumpWidget(progress(t, running: false));
      expect(find.textContaining('五代十国'), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.tap(find.byKey(const Key('agent-progress-toggle')));
      await tester.pump();
      expect(
        find.text('五代十国 · ${F('i18n.agent_found_sources', [3])}'),
        findsOneWidget,
      );
      expect(find.text(T('i18n.agent_progress_collapse')), findsOneWidget);
    },
  );

  testWidgets(
    'queued calls never hide the executing step; all history can be expanded',
    (tester) async {
      final t = task();
      t.steps.addAll([
        for (var i = 0; i < 4; i++)
          {
            'name': 'search_project',
            'status': 'completed',
            'arguments': {'query': 'old $i'},
          },
        {
          'name': 'read_webpage',
          'status': 'running',
          'arguments': {'url': 'https://current.example.com/path'},
        },
        for (var i = 0; i < 5; i++)
          {
            'name': 'save_artifact',
            'status': 'pending',
            'arguments': {'name': 'planned-$i.pdf'},
          },
      ]);
      t.pending.add({'name': 'read_webpage', 'step': 4});
      await tester.pumpWidget(progress(t));
      expect(find.text('current.example.com'), findsOneWidget);
      expect(find.text('old 0'), findsNothing);
      expect(find.text('old 2'), findsOneWidget);
      expect(find.text('planned-4.pdf'), findsNothing);
      await tester.tap(find.byKey(const Key('agent-progress-toggle')));
      await tester.pump();
      expect(find.text('old 0'), findsOneWidget);
      expect(find.text('planned-4.pdf'), findsOneWidget);
    },
  );

  testWidgets('paused steps show interruption without a running spinner', (
    tester,
  ) async {
    final t = task()..status = 'paused';
    t.steps.add({
      'name': 'save_artifact',
      'status': 'running',
      'arguments': {'name': '报告.pdf'},
    });
    await tester.pumpWidget(progress(t, running: false));
    expect(
      find.text(
        '${T('i18n.agent_tool_save')} · ${T('i18n.agent_interrupted')}',
      ),
      findsOneWidget,
    );
    expect(find.text('报告.pdf'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.byIcon(CupertinoIcons.pause_circle), findsOneWidget);
  });
}
