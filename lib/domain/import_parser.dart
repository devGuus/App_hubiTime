/// Leitura e validação dos arquivos de importação (.csv, .txt, .xlsx).
/// Porte de hubi-time-web/src/lib/import-service.ts: mesmos cabeçalhos, mesmos
/// formatos de data/hora e mesmo conjunto de tipos de dia.
///
/// Acréscimos do app sobre o site (validação, não mudança de formato): limite
/// de tamanho/linhas, cabeçalho "Data" obrigatório, data inexistente e data
/// repetida dentro do próprio arquivo.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../core/constants.dart';
import '../core/dates.dart';
import 'validators.dart';

const importHeaders = ['Data', 'Entrada', 'Saida almoco', 'Retorno', 'Saida', 'Tipo de dia', 'Observacoes'];

const maxImportFileBytes = 5 * 1024 * 1024;
const maxImportRows = 5000;
const importExtensions = ['csv', 'txt', 'xlsx'];

class ImportFileException implements Exception {
  const ImportFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ParsedImportRow {
  ParsedImportRow({
    required this.rowNumber,
    this.workDate,
    this.entryTime,
    this.lunchStart,
    this.lunchEnd,
    this.exitTime,
    this.dayType = DayType.normal,
    this.notes,
    List<String>? errors,
    List<String>? warnings,
  })  : errors = errors ?? [],
        warnings = warnings ?? [];

  final int rowNumber;
  final DateISO? workDate;
  final String? entryTime;
  final String? lunchStart;
  final String? lunchEnd;
  final String? exitTime;
  final DayType dayType;
  final String? notes;
  final List<String> errors;
  final List<String> warnings;
}

String _normalize(String text) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  final buffer = StringBuffer();
  for (final rune in text.trim().runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    buffer.write(i >= 0 ? to[i] : ch);
  }
  return buffer.toString().toLowerCase();
}

final Map<String, DayType> _labelToDayType = {
  for (final t in DayType.values) ...{_normalize(t.label): t, _normalize(t.key): t},
};

String? _parseTime(String raw, String field, List<String> errors) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(text);
  if (m == null) {
    errors.add('$field: horário inválido ("$text"), use o formato HH:MM.');
    return null;
  }
  final h = int.parse(m[1]!), min = int.parse(m[2]!);
  if (h > 23 || min > 59) {
    errors.add('$field: horário inválido ("$text").');
    return null;
  }
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

DateISO? _parseDate(String raw, List<String> errors) {
  final text = raw.trim();
  if (text.isEmpty) {
    errors.add('Data: campo obrigatório.');
    return null;
  }
  DateISO? iso;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    iso = text;
  } else if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(text)) {
    final p = text.split('/');
    iso = '${p[2]}-${p[1].padLeft(2, '0')}-${p[0].padLeft(2, '0')}';
  } else {
    errors.add('Data: formato inválido ("$text"), use DD/MM/AAAA.');
    return null;
  }
  if (!isValidIsoDate(iso)) {
    errors.add('Data: "$text" não existe no calendário.');
    return null;
  }
  return iso;
}

DayType _parseDayType(String raw, List<String> errors) {
  final text = raw.trim();
  if (text.isEmpty) return DayType.normal;
  final found = _labelToDayType[_normalize(text)];
  if (found == null) {
    errors.add('Tipo de dia: valor desconhecido ("$text"), usando "Dia normal".');
    return DayType.normal;
  }
  return found;
}

ParsedImportRow _toRow(int rowNumber, Map<String, String> cells) {
  final errors = <String>[];
  final workDate = _parseDate(cells['Data'] ?? '', errors);
  final entry = _parseTime(cells['Entrada'] ?? '', 'Entrada', errors);
  final lunchStart = _parseTime(cells['Saida almoco'] ?? '', 'Saida almoco', errors);
  final lunchEnd = _parseTime(cells['Retorno'] ?? '', 'Retorno', errors);
  final exit = _parseTime(cells['Saida'] ?? '', 'Saida', errors);
  final dayType = _parseDayType(cells['Tipo de dia'] ?? '', errors);
  final notes = (cells['Observacoes'] ?? '').trim();
  return ParsedImportRow(
    rowNumber: rowNumber,
    workDate: workDate,
    entryTime: entry,
    lunchStart: lunchStart,
    lunchEnd: lunchEnd,
    exitTime: exit,
    dayType: dayType,
    notes: notes.isEmpty ? null : notes,
    errors: errors,
    warnings: detectTimeInconsistencies(entry, lunchStart, lunchEnd, exit).map((w) => w.message).toList(),
  );
}

/// CSV simples (aspas para campos com vírgula/ponto e vírgula) - mesmo
/// comportamento do site: "," e ";" são ambos separadores.
List<List<String>> parseCsvText(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
      continue;
    }
    if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',' || ch == ';') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n') {
      row.add(field.toString());
      rows.add(row);
      row = <String>[];
      field.clear();
    } else if (ch != '\r') {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}

String _cellText(CellValue? value) {
  switch (value) {
    case null:
      return '';
    case DateCellValue(:final year, :final month, :final day):
      return toIso(DateTime(year, month, day));
    case DateTimeCellValue(:final year, :final month, :final day):
      return toIso(DateTime(year, month, day));
    case TimeCellValue(:final hour, :final minute):
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    default:
      return value.toString();
  }
}

List<ParsedImportRow> _rowsFromTable(List<List<String>> table) {
  if (table.isEmpty) return [];
  final headers = table.first.map((h) => h.trim()).toList();
  if (!headers.contains('Data')) {
    throw const ImportFileException(
      'Não encontrei a coluna "Data" na primeira linha. Use o modelo do Hubi Time: '
      'Data, Entrada, Saida almoco, Retorno, Saida, Tipo de dia, Observacoes.',
    );
  }
  final rows = <ParsedImportRow>[];
  for (var i = 1; i < table.length; i++) {
    final cells = <String, String>{};
    for (var c = 0; c < headers.length; c++) {
      if (headers[c].isEmpty) continue;
      cells[headers[c]] = c < table[i].length ? table[i][c] : '';
    }
    rows.add(_toRow(i + 1, cells));
  }
  return rows;
}

/// Marca como erro a segunda ocorrência de uma data dentro do mesmo arquivo.
void _flagDuplicateDates(List<ParsedImportRow> rows) {
  final seen = <DateISO, int>{};
  for (final row in rows) {
    final date = row.workDate;
    if (date == null || row.errors.isNotEmpty) continue;
    final first = seen[date];
    if (first != null) {
      row.errors.add('Data repetida no arquivo (já aparece na linha $first).');
    } else {
      seen[date] = row.rowNumber;
    }
  }
}

/// Lê [bytes] de um arquivo chamado [fileName]. Lança [ImportFileException]
/// com mensagem para o usuário quando o arquivo não pode ser usado.
List<ParsedImportRow> parseImportFile(String fileName, Uint8List bytes) {
  final name = fileName.toLowerCase();
  final isCsv = name.endsWith('.csv') || name.endsWith('.txt');
  final isXlsx = name.endsWith('.xlsx');
  if (!isCsv && !isXlsx) {
    throw const ImportFileException('Formato de arquivo não suportado. Envie um arquivo .csv, .txt ou .xlsx.');
  }
  if (bytes.isEmpty) throw const ImportFileException('O arquivo está vazio.');
  if (bytes.length > maxImportFileBytes) {
    throw const ImportFileException('Arquivo muito grande (limite de 5 MB). Divida em arquivos menores.');
  }

  List<List<String>> table;
  try {
    if (isCsv) {
      table = parseCsvText(utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', ''));
    } else {
      final sheets = Excel.decodeBytes(bytes).tables.values;
      if (sheets.isEmpty) return [];
      table = sheets.first.rows
          .map((r) => r.map((cell) => _cellText(cell?.value)).toList())
          .where((r) => r.any((c) => c.trim().isNotEmpty))
          .toList();
    }
  } on ImportFileException {
    rethrow;
  } catch (_) {
    throw const ImportFileException('Não consegui ler o arquivo. Confirme que ele não está corrompido e tente de novo.');
  }

  if (table.length - 1 > maxImportRows) {
    throw const ImportFileException('Arquivo com linhas demais (limite de 5000). Divida em arquivos menores.');
  }
  final rows = _rowsFromTable(table);
  _flagDuplicateDates(rows);
  return rows;
}

const _templateRows = [
  ['01/03/2026', '08:00', '12:00', '13:00', '17:00', 'Dia normal', ''],
  ['02/03/2026', '', '', '', '', 'Folga', 'Exemplo de dia sem expediente'],
];

/// Mesmo modelo CSV do site (separador ";", BOM UTF-8).
String importTemplateCsv() {
  final lines = [importHeaders.join(';'), ..._templateRows.map((r) => r.join(';'))];
  return '﻿${lines.join('\r\n')}';
}

List<int> importTemplateXlsx() {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(sheetName, 'Modelo');
  final sheet = excel['Modelo'];
  sheet.appendRow(importHeaders.map<CellValue?>((h) => TextCellValue(h)).toList());
  for (final r in _templateRows) {
    sheet.appendRow(r.map<CellValue?>((c) => TextCellValue(c)).toList());
  }
  return excel.encode() ?? <int>[];
}
