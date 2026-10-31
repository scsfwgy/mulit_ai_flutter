import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mulit_ai_flutter/agent/agent_artifact_format.dart';
import 'package:mulit_ai_flutter/agent/agent_csv.dart';
import 'package:xml/xml.dart';

const _report = '''# 项目整理报告

这份报告验证中文、English、**重点内容**、*引用说明*，以及符号 & < > 的正确保存。

## 建议与执行

1. 先确认资料来源与更新时间。
2. 保留已经完成的工作，按补充要求继续。

- 支持离线生成文件。
- 成果可保存为项目笔记。

| 项目 | 结果 | 说明 |
| --- | --- | --- |
| 模型检查 | 通过 | 工具调用与结果回复 |
| 文档导出 | 已生成 | PDF、Word、Markdown |
| 表格导出 | 已生成 | Excel、CSV |

参考：[示例来源](https://example.com/report?a=1&b=2)。

```text
first line
第二行
```
''';
const _csv =
    '项目,数量,编号,说明\n模型检查,2,00123,"保留前导零"\n文档导出,12.5,00234,"中文换行\n第二行"\n安全内容,-3,00345,"=SUM(A1:A2)"\n其他,0,00456,"+cmd|example"';

Map<String, XmlDocument> _parts(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  return {
    for (final file in archive.files.where(
      (f) => f.name.endsWith('.xml') || f.name.endsWith('.rels'),
    ))
      file.name: XmlDocument.parse(utf8.decode(file.content)),
  };
}

void main() {
  test(
    'offline Chinese PDF font is present in the application asset bundle',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final font = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      expect(font.lengthInBytes, greaterThan(1000000));
      final pdf = await encodeAgentArtifact(
        AgentArtifactFormat.pdf,
        '# 中文标题\n\n离线内容。',
      );
      expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
    },
  );

  test(
    'real Office encoders preserve Chinese and types without formulas',
    () async {
      final word = _parts(
        await encodeAgentArtifact(AgentArtifactFormat.word, _report),
      );
      expect(
        word.keys,
        containsAll([
          '[Content_Types].xml',
          'word/document.xml',
          'word/styles.xml',
        ]),
      );
      final doc = word['word/document.xml']!;
      expect(doc.findAllElements('w:tbl'), hasLength(1));
      expect(doc.findAllElements('w:tblHeader'), hasLength(1));
      expect(doc.innerText, contains('项目整理报告'));
      expect(doc.innerText, contains('https://example.com/report?a=1&b=2'));
      expect(doc.findAllElements('w:br'), isNotEmpty);
      final excel = _parts(
        await encodeAgentArtifact(AgentArtifactFormat.excel, _csv),
      );
      final sheet = excel['xl/worksheets/sheet1.xml']!;
      XmlElement cell(String name) => sheet
          .findAllElements('c')
          .firstWhere((c) => c.getAttribute('r') == name);
      expect(cell('B2').findElements('v').single.innerText, '2');
      expect(cell('B4').findElements('v').single.innerText, '-3');
      expect(cell('C2').getAttribute('t'), 'inlineStr');
      expect(cell('C2').innerText, '00123');
      expect(cell('D4').getAttribute('t'), 'inlineStr');
      expect(cell('D4').innerText, '=SUM(A1:A2)');
      expect(sheet.findAllElements('f'), isEmpty);
      expect(
        sheet.findAllElements('pane').single.getAttribute('state'),
        'frozen',
      );
      final csv = utf8.decode(
        await encodeAgentArtifact(AgentArtifactFormat.csv, _csv),
      );
      expect(parseAgentCsv(csv)[3][3], "'=SUM(A1:A2)");
      expect(
        await encodeAgentArtifact(AgentArtifactFormat.markdown, _report),
        utf8.encode(_report),
      );
    },
  );

  test('PDF embeds offline Chinese font, long text and multipage tables', () async {
    final long =
        '$_report\n## 详细记录\n\n${List.generate(30, (i) => '第 ${i + 1} 段：按用户要求保留已完成工作。' * 7).join('\n\n')}\n\n|序号|说明|\n|---|---|\n${List.generate(90, (i) => '|${i + 1}|中文表格跨页内容 $i|').join('\n')}';
    final font = await File('assets/fonts/NotoSansSC-Regular.ttf')
        .readAsBytes();
    final pdf = await encodeAgentArtifact(
      AgentArtifactFormat.pdf,
      long,
      loadPdfFont: () async => font,
    );
    expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
    final raw = latin1.decode(pdf);
    expect(raw, contains('/FontFile2'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, greaterThan(2));
    const qa = String.fromEnvironment('AGENT_ARTIFACT_QA');
    if (qa.isNotEmpty) {
      await Directory(qa).create(recursive: true);
      await File('$qa/report.pdf').writeAsBytes(pdf);
      await File('$qa/report.docx').writeAsBytes(
        await encodeAgentArtifact(AgentArtifactFormat.word, _report),
      );
      await File('$qa/report.xlsx').writeAsBytes(
        await encodeAgentArtifact(AgentArtifactFormat.excel, _csv),
      );
    }
  });

  test(
    'invalid or oversized inputs fail instead of corrupting a file',
    () async {
      for (final format in AgentArtifactFormat.values) {
        await expectLater(
          encodeAgentArtifact(format, ' '),
          throwsFormatException,
        );
        await expectLater(
          encodeAgentArtifact(format, 'a\u0000b'),
          throwsFormatException,
        );
        await expectLater(
          encodeAgentArtifact(format, '中' * 40001),
          throwsFormatException,
        );
      }
      await expectLater(
        encodeAgentArtifact(AgentArtifactFormat.excel, 'a,b\n"unterminated'),
        throwsFormatException,
      );
      await expectLater(
        encodeAgentArtifact(AgentArtifactFormat.excel, 'a\n"${'line\n' * 26}"'),
        throwsFormatException,
      );
    },
  );
}
