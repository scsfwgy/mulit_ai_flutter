List<List<String>> parseAgentCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  var closed = false;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      if (cell.isNotEmpty || closed) throw const FormatException('CSV quote');
      quoted = true;
    } else if (c == ',' || c == '\n' || c == '\r') {
      row.add(cell.toString());
      cell = StringBuffer();
      closed = false;
      if (c != ',') {
        rows.add(row);
        row = [];
        if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      }
    } else {
      if (closed) throw const FormatException('CSV trailing text');
      cell.write(c);
    }
  }
  if (quoted) throw const FormatException('CSV unclosed quote');
  if (cell.isNotEmpty || closed || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// Quote cells and neutralize spreadsheet formula prefixes in CSV exports.
String safeAgentCsv(String input) {
  final rows = parseAgentCsv(input);
  return rows
      .map(
        (row) => row
            .map((cell) {
              final text =
                  RegExp(r'^[=+@\-]').hasMatch(cell.trimLeft()) ||
                      cell.startsWith('\t')
                  ? "'$cell"
                  : cell;
              return '"${text.replaceAll('"', '""')}"';
            })
            .join(','),
      )
      .join('\r\n');
}
