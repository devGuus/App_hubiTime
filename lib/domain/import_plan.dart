/// Classificação das linhas lidas do arquivo frente ao que já existe no
/// servidor (mesma lógica de statusOf em importar/page.tsx).
library;

import '../core/dates.dart';
import 'import_parser.dart';
import 'models.dart';

enum ImportStatus { novo, conflito, erro }

class ReviewRow {
  ReviewRow({required this.parsed, required this.status, this.existing, this.overwrite = false});

  final ParsedImportRow parsed;
  final ImportStatus status;
  final WorkRecord? existing;

  /// Só vale para [ImportStatus.conflito]: o usuário autorizou sobrescrever.
  bool overwrite;
}

List<ReviewRow> classifyRows(List<ParsedImportRow> rows, Map<DateISO, WorkRecord> existingByDate) {
  return rows.map((row) {
    if (row.errors.isNotEmpty || row.workDate == null) {
      return ReviewRow(parsed: row, status: ImportStatus.erro);
    }
    final existing = existingByDate[row.workDate];
    return ReviewRow(
      parsed: row,
      status: existing != null ? ImportStatus.conflito : ImportStatus.novo,
      existing: existing,
    );
  }).toList();
}

/// Intervalo de datas válidas do arquivo, para buscar só o necessário no servidor.
(DateISO, DateISO)? dateSpan(List<ParsedImportRow> rows) {
  final dates = rows.map((r) => r.workDate).whereType<DateISO>().toList()..sort();
  return dates.isEmpty ? null : (dates.first, dates.last);
}
