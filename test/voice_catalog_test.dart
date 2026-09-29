import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mulit_ai_flutter/data.dart';
import 'package:mulit_ai_flutter/voice_catalog.dart';
import 'package:mulit_ai_flutter/voice_catalog_picker.dart';

void main() {
  test(
    'Doubao suggestions only expose resources used by current endpoints',
    () {
      final asr = voiceCatalogExamples(
        VoiceProtocol.doubao,
        VoiceCatalogKind.asr,
      );
      final tts = voiceCatalogExamples(
        VoiceProtocol.doubao,
        VoiceCatalogKind.tts,
      );
      expect(asr.map((item) => item.id), ['volc.bigasr.auc_turbo']);
      expect(tts.map((item) => item.id), ['seed-tts-2.0']);
      final voices = voiceCatalogExamples(
        VoiceProtocol.doubao,
        VoiceCatalogKind.voice,
      );
      expect(voices, hasLength(8));
      expect(voices.map((item) => item.id).toSet(), hasLength(8));
      expect(voices.every((item) => !item.id.startsWith('ICL_')), isTrue);
    },
  );

  test('MiMo server list excludes voice design and clone models', () async {
    final client = VoiceCatalogClient(
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://api.xiaomimimo.com/v1/models');
        expect(request.headers['Authorization'], 'Bearer demo-key');
        expect(request.followRedirects, isFalse);
        return http.Response('''{"data":[
          {"id":"mimo-v2.5-tts-voiceclone"},
          {"id":"mimo-v2.5-tts"},
          {"id":"mimo-v2.5-tts-voicedesign"},
          {"id":"mimo-v2.5-asr"}
        ]}''', 200);
      }),
    );
    final options = await client.fetchModels(
      baseUrl: 'https://api.xiaomimimo.com/v1',
      apiKey: 'demo-key',
      protocol: VoiceProtocol.mimo,
      kind: VoiceCatalogKind.tts,
    );
    expect(options.map((item) => item.id), ['mimo-v2.5-tts']);
  });

  test(
    'server errors and malformed bodies cannot disclose their content',
    () async {
      for (final response in [
        http.Response('secret demo-key', 401),
        http.Response('secret demo-key', 200),
      ]) {
        final client = VoiceCatalogClient(
          client: MockClient((_) async => response),
        );
        await expectLater(
          client.fetchModels(
            baseUrl: 'https://api.example.com/v1',
            apiKey: 'demo-key',
            protocol: VoiceProtocol.openAi,
            kind: VoiceCatalogKind.asr,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              isNot(contains('demo-key')),
            ),
          ),
        );
      }
    },
  );

  testWidgets('Doubao examples can be selected without a network request', (
    tester,
  ) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                chosen = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VoiceCatalogPicker(
                      title: '选择音色',
                      examples: voiceCatalogExamples(
                        VoiceProtocol.doubao,
                        VoiceCatalogKind.voice,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('官方示例'), findsOneWidget);
    await tester.tap(find.text('zh_female_vv_uranus_bigtts'));
    await tester.pumpAndSettle();
    expect(chosen, 'zh_female_vv_uranus_bigtts');
  });

  testWidgets('picker accepts a manually entered voice ID', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                chosen = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VoiceCatalogPicker(
                      title: '选择音色',
                      examples: voiceCatalogExamples(
                        VoiceProtocol.doubao,
                        VoiceCatalogKind.voice,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('手动输入 ID'));
    await tester.tap(find.text('手动输入 ID'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField).last,
      ' custom_voice ',
    );
    await tester.tap(find.text('使用此 ID'));
    await tester.pumpAndSettle();
    expect(chosen, 'custom_voice');
  });
}
