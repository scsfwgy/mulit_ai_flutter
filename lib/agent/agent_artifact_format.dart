import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';
import 'package:mulit_ai_flutter/agent/agent_csv.dart';

enum AgentArtifactFormat {
  markdown('md', 'Markdown', 'text/markdown'),
  csv('csv', 'CSV', 'text/csv'),
  pdf('pdf', 'PDF', 'application/pdf'),
  word(
    'docx',
    'Word',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  excel(
    'xlsx',
    'Excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );

  const AgentArtifactFormat(this.extension, this.label, this.mimeType);
  final String extension;
  final String label;
  final String mimeType;
  bool get table => this == csv || this == excel;
  bool get binary => this == pdf || this == word || this == excel;
  static AgentArtifactFormat? forName(String name) => values
      .where((f) => name.toLowerCase().endsWith('.${f.extension}'))
      .firstOrNull;
}

Future<Uint8List>? _pdfFont;

/// The model supplies text, never ZIP/XML/PDF bytes. Encoding is entirely local.
Future<Uint8List> encodeAgentArtifact(
  AgentArtifactFormat format,
  String content, {
  Future<Uint8List> Function()? loadPdfFont,
}) async {
  if (content.trim().isEmpty ||
      utf8.encode(content).length > 120000 ||
      content.runes.any(
        (r) =>
            !(r == 9 ||
                r == 10 ||
                r == 13 ||
                r >= 0x20 && r <= 0xd7ff ||
                r >= 0xe000 && r <= 0xfffd ||
                r >= 0x10000 && r <= 0x10ffff),
      )) {
    throw const FormatException('Artifact content');
  }
  if (format == AgentArtifactFormat.markdown) {
    return Uint8List.fromList(utf8.encode(content));
  }
  if (format == AgentArtifactFormat.csv) {
    return Uint8List.fromList(utf8.encode(safeAgentCsv(content)));
  }
  Uint8List? font;
  if (format == AgentArtifactFormat.pdf) {
    font =
        await (loadPdfFont?.call() ??
            (_pdfFont ??= rootBundle
                .load('assets/fonts/NotoSansSC-Regular.ttf')
                .then(
                  (b) => b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes),
                )));
  }
  final bytes = font;
  return Isolate.run(
    () => switch (format) {
      AgentArtifactFormat.excel => _xlsx(content),
      AgentArtifactFormat.word => _docx(content),
      AgentArtifactFormat.pdf => _pdf(content, bytes!),
      _ => throw const FormatException('Artifact format'),
    },
  );
}

String _x(String value) => XmlText(value).toXmlString();
Uint8List _zip(Map<String, String> parts) {
  final archive = Archive();
  for (final entry in parts.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

List<md.Node> _markdown(String source) => md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  encodeHtml: false,
).parseLines(source.split('\n'));

List<List<String>> _table(md.Element element) {
  final rows = <List<String>>[];
  void visit(md.Node node) {
    if (node is! md.Element) return;
    if (node.tag == 'tr') {
      rows.add([
        for (final cell in node.children ?? <md.Node>[]) cell.textContent,
      ]);
    } else {
      for (final child in node.children ?? <md.Node>[]) {
        visit(child);
      }
    }
  }

  visit(element);
  return rows;
}

List<double> _widths(List<List<String>> rows) {
  final count = rows.fold(0, (n, row) => math.max(n, row.length));
  return [
    for (var col = 0; col < count; col++)
      rows
          .map((row) => col < row.length ? row[col].runes.length : 0)
          .fold(8, math.max)
          .clamp(8, 40)
          .toDouble(),
  ];
}

Uint8List _xlsx(String content) {
  final rows = parseAgentCsv(content);
  if (rows.isEmpty ||
      rows.length > 2000 ||
      rows.any((r) => r.length > 50 || r.any((c) => c.length > 32000))) {
    throw const FormatException('Spreadsheet size');
  }
  final widths = _widths(rows);
  String column(int n) {
    var label = '';
    do {
      label = String.fromCharCode(65 + n % 26) + label;
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return label;
  }

  String cell(String text, String address, bool header) {
    final number =
        RegExp(r'^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$')
                .hasMatch(text) &&
            text.replaceAll(RegExp(r'[^0-9]'), '').length <= 15
        ? num.tryParse(text)
        : null;
    if (!header && number != null && number.isFinite) {
      return '<c r="$address" s="1"><v>$number</v></c>';
    }
    return '<c r="$address" s="${header ? 2 : 1}" t="inlineStr"><is><t xml:space="preserve">${_x(text)}</t></is></c>';
  }

  final data = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final lines = [
      for (var c = 0; c < row.length; c++)
        (row[c].runes.length / widths[c]).ceil() +
            '\n'.allMatches(row[c]).length,
    ].fold(1, math.max);
    if (lines > 24) {
      throw const FormatException('Spreadsheet cell too tall; split into rows');
    }
    data.write(
      '<row r="${r + 1}" ht="${math.max(24, lines * 16 + 10).clamp(24, 409)}" customHeight="1">',
    );
    for (var c = 0; c < row.length; c++) {
      data.write(cell(row[c], '${column(c)}${r + 1}', r == 0));
    }
    data.write('</row>');
  }
  return _zip({
    '[Content_Types].xml': '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml': '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Microsoft YaHei"/></font><font><b/><sz val="11"/><name val="Microsoft YaHei"/><color rgb="FF000000"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFDCEAF7"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border/><border><left style="thin"><color rgb="FFD9D9D9"/></left><right style="thin"><color rgb="FFD9D9D9"/></right><top style="thin"><color rgb="FFD9D9D9"/></top><bottom style="thin"><color rgb="FFD9D9D9"/></bottom></border></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="3"><xf/><xf fontId="0" fillId="0" borderId="1" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
    'xl/worksheets/sheet1.xml':
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>${[for (var i = 0; i < widths.length; i++) '<col min="${i + 1}" max="${i + 1}" width="${(widths[i] * 1.3 + 3).clamp(12, 55)}" customWidth="1"/>'].join()}</cols><sheetData>$data</sheetData><autoFilter ref="A1:${column(widths.length - 1)}${rows.length}"/></worksheet>',
  });
}

Uint8List _docx(String content) {
  final nodes = _markdown(content);
  var firstTitle = true;
  var wide = false;
  String runs(
    List<md.Node> nodes, {
    bool bold = false,
    bool italic = false,
  }) => nodes.map((node) {
    if (node is md.Text) {
      return '<w:r><w:rPr>${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}</w:rPr><w:t xml:space="preserve">${_x(node.text).replaceAll('\n', '</w:t><w:br/><w:t xml:space="preserve">')}</w:t></w:r>';
    }
    final element = node as md.Element;
    if (element.tag == 'br') return '<w:r><w:br/></w:r>';
    final text = runs(
      element.children ?? [],
      bold: bold || element.tag == 'strong',
      italic: italic || element.tag == 'em',
    );
    return element.tag == 'a' && element.attributes['href'] != null
        ? '$text<w:r><w:t xml:space="preserve"> (${_x(element.attributes['href']!)})</w:t></w:r>'
        : text;
  }).join();
  String paragraph(md.Element element, {String? prefix}) {
    final heading = RegExp(r'^h[1-6]$').hasMatch(element.tag);
    final style = heading
        ? firstTitle && element.tag == 'h1'
              ? 'Title'
              : 'Heading${element.tag.substring(1)}'
        : element.tag == 'pre'
        ? 'Code'
        : 'Normal';
    if (heading) firstTitle = false;
    return '<w:p><w:pPr><w:pStyle w:val="$style"/>${prefix == null ? '' : '<w:ind w:left="360" w:hanging="240"/>'}</w:pPr>${prefix == null ? '' : '<w:r><w:t xml:space="preserve">${_x(prefix)} </w:t></w:r>'}${runs(element.children ?? [])}</w:p>';
  }

  String blocks(List<md.Node> nodes) => nodes.map((node) {
    if (node is! md.Element) return '<w:p>${runs([node])}</w:p>';
    if (node.tag == 'table') {
      final rows = _table(node);
      final widths = _widths(rows);
      if (widths.isEmpty || widths.length > 12) {
        throw const FormatException('Document table size');
      }
      wide |= widths.length > 5;
      final total = widths.reduce((a, b) => a + b);
      final usable = widths.length > 5 ? 14400 : 9600;
      return '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblLayout w:type="fixed"/><w:tblBorders>${[
        for (final side in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) '<w:$side w:val="single" w:sz="4" w:color="D9D9D9"/>',
      ].join()}</w:tblBorders><w:tblCellMar><w:top w:w="100" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>${widths.map((w) => '<w:gridCol w:w="${(usable * w / total).round()}"/>').join()}</w:tblGrid>${[
        for (var r = 0; r < rows.length; r++) '<w:tr>${r == 0 ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}${[
            for (var c = 0; c < widths.length; c++) '<w:tc><w:tcPr><w:tcW w:w="${(usable * widths[c] / total).round()}" w:type="dxa"/><w:vAlign w:val="center"/>${r == 0 ? '<w:shd w:fill="DCEAF7"/>' : ''}</w:tcPr><w:p>${runs([md.Text(c < rows[r].length ? rows[r][c] : '')], bold: r == 0)}</w:p></w:tc>',
          ].join()}</w:tr>',
      ].join()}</w:tbl><w:p/>';
    }
    if (node.tag == 'ul' || node.tag == 'ol') {
      var number = 0;
      return (node.children ?? [])
          .whereType<md.Element>()
          .map(
            (li) =>
                paragraph(li, prefix: node.tag == 'ul' ? '•' : '${++number}.'),
          )
          .join();
    }
    if (node.tag == 'blockquote') return blocks(node.children ?? []);
    return paragraph(node);
  }).join();
  final body = blocks(nodes);
  return _zip({
    '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>',
    '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/_rels/document.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'word/styles.xml':
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Microsoft YaHei"/><w:sz w:val="22"/><w:color w:val="000000"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="140" w:line="300" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/><w:color w:val="000000"/></w:rPr></w:style>${[for (var i = 1; i <= 6; i++) '<w:style w:type="paragraph" w:styleId="Heading$i"><w:name w:val="heading $i"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="220" w:after="120"/><w:outlineLvl w:val="${i - 1}"/></w:pPr><w:rPr><w:b/><w:sz w:val="${math.max(24, 36 - i * 3)}"/><w:color w:val="000000"/></w:rPr></w:style>'].join()}<w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="19"/></w:rPr></w:style></w:styles>',
    'word/document.xml':
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$body<w:sectPr><w:pgSz w:w="${wide ? 16838 : 11906}" w:h="${wide ? 11906 : 16838}"${wide ? ' w:orient="landscape"' : ''}/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr></w:body></w:document>',
  });
}

String _plain(md.Node node) {
  if (node is md.Text) return node.text;
  final element = node as md.Element;
  if (element.tag == 'br') return '\n';
  if (element.tag == 'img') return element.attributes['alt'] ?? '';
  final text = (element.children ?? <md.Node>[]).map(_plain).join();
  final url = element.attributes['href'];
  return element.tag == 'a' && url != null ? '$text ($url)' : text;
}

Future<Uint8List> _pdf(String content, Uint8List fontBytes) async {
  final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
  final document = pw.Document(
    theme: pw.ThemeData.withFont(
      base: font,
      bold: font,
      italic: font,
      boldItalic: font,
    ),
    author: 'AI Link',
  );
  final nodes = _markdown(content);
  List<pw.Widget> blocks(List<md.Node> nodes) {
    final result = <pw.Widget>[];
    for (final node in nodes) {
      if (node is! md.Element) {
        result.add(pw.Text(_plain(node)));
        continue;
      }
      if (node.tag == 'table') {
        final rows = _table(node);
        if (rows.any((r) => r.length > 12)) {
          throw const FormatException('PDF table size');
        }
        final widths = _widths(rows);
        result.add(
          pw.TableHelper.fromTextArray(
            data: rows,
            cellStyle: pw.TextStyle(
              font: font,
              fontSize: widths.length > 5 ? 8 : 9,
            ),
            headerStyle: pw.TextStyle(font: font, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xffdceaf7),
            ),
            border: pw.TableBorder.all(
              color: const PdfColor.fromInt(0xffd9d9d9),
              width: .5,
            ),
            cellPadding: const pw.EdgeInsets.all(6),
            columnWidths: {
              for (var i = 0; i < widths.length; i++)
                i: pw.FlexColumnWidth(widths[i]),
            },
          ),
        );
      } else if (node.tag == 'ul' || node.tag == 'ol') {
        var number = 0;
        for (final child in node.children ?? []) {
          result.add(
            pw.Text(
              '${node.tag == 'ul' ? '•' : '${++number}.'} ${_plain(child)}',
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
            ),
          );
        }
      } else if (node.tag == 'blockquote') {
        result.addAll(blocks(node.children ?? []));
      } else {
        final heading = RegExp(r'^h[1-6]$').hasMatch(node.tag);
        result.add(
          pw.Text(
            _plain(node),
            style: pw.TextStyle(
              fontSize: heading
                  ? 23 - int.parse(node.tag.substring(1)) * 1.7
                  : node.tag == 'pre'
                  ? 9
                  : 11,
              lineSpacing: 4,
            ),
          ),
        );
      }
      result.add(pw.SizedBox(height: 10));
    }
    return result;
  }

  final wide = nodes
      .whereType<md.Element>()
      .where((e) => e.tag == 'table')
      .any((e) => _table(e).any((r) => r.length > 5));
  document.addPage(
    pw.MultiPage(
      pageFormat: wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(42),
      maxPages: 100,
      build: (_) => blocks(nodes),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${context.pageNumber}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
    ),
  );
  return document.save();
}
