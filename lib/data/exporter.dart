/// Geração dos arquivos de relatório (.xlsx, .csv, .pdf) e compartilhamento
/// pela folha de compartilhamento do sistema (salvar em Arquivos, enviar por
/// e-mail/WhatsApp etc.). Mesmos cabeçalhos e conteúdo do site.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/report.dart';

/// CSV com BOM e ";" como separador, como no site. Um ";" dentro de uma
/// célula vira "," (o site também não usa aspas).
Uint8List buildCsv(ReportTable table) {
  final lines = [
    table.headers.join(';'),
    for (final row in table.rows) table.headers.map((h) => (row[h] ?? '').replaceAll(';', ',')).join(';'),
  ];
  return Uint8List.fromList(utf8.encode('﻿${lines.join('\r\n')}'));
}

Uint8List buildXlsx(ReportTable table) {
  final excel = Excel.createExcel();
  final sheetName = table.title.length > 31 ? table.title.substring(0, 31) : table.title;
  excel.rename(excel.getDefaultSheet() ?? 'Sheet1', sheetName);
  final sheet = excel[sheetName];

  final headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('#1F2937'),
  );
  sheet.appendRow(table.headers.map<CellValue?>((h) => TextCellValue(h)).toList());
  for (var c = 0; c < table.headers.length; c++) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = headerStyle;
  }
  for (final row in table.rows) {
    sheet.appendRow(table.headers.map<CellValue?>((h) => TextCellValue(row[h] ?? '')).toList());
  }
  for (var c = 0; c < table.headers.length; c++) {
    final header = table.headers[c];
    final longest = table.rows.fold<int>(header.length, (m, r) => math.max(m, (r[header] ?? '').length));
    sheet.setColumnWidth(c, math.min(longest + 4, 40).toDouble());
  }
  return Uint8List.fromList(excel.encode() ?? const []);
}

Future<Uint8List> buildPdf(ReportTable table) async {
  final doc = pw.Document();
  final headerStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text(table.title, style: const pw.TextStyle(fontSize: 14)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: table.headers,
          data: [for (final row in table.rows) table.headers.map((h) => row[h] ?? '').toList()],
          headerStyle: headerStyle,
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1F2937)),
          cellStyle: const pw.TextStyle(fontSize: 8),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF9FAFB)),
        ),
      ],
    ),
  );
  return doc.save();
}

Future<Uint8List> buildExport(ReportTable table, ExportFormat format) async {
  switch (format) {
    case ExportFormat.csv:
      return buildCsv(table);
    case ExportFormat.xlsx:
      return buildXlsx(table);
    case ExportFormat.pdf:
      return buildPdf(table);
  }
}

String _mimeOf(String fileName) {
  if (fileName.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  if (fileName.endsWith('.pdf')) return 'application/pdf';
  return 'text/csv';
}

/// Grava [bytes] numa pasta temporária e abre o compartilhamento do sistema.
Future<void> shareFile(String fileName, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: _mimeOf(fileName))]));
}
