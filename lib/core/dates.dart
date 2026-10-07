/// Datas de jornada circulam como "YYYY-MM-DD" (igual ao Postgres e ao site),
/// sempre em horário local - nunca via UTC, para não "voltar um dia" no Brasil.
library;

import 'constants.dart';

typedef DateISO = String;

String _pad2(int n) => n.toString().padLeft(2, '0');

String toIso(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${_pad2(date.month)}-${_pad2(date.day)}';

DateTime toLocalDate(DateISO iso) {
  final parts = iso.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

DateISO todayIso([DateTime? now]) => toIso(now ?? DateTime.now());

WeekdayKey weekdayKeyOf(DateISO iso) => WeekdayKey.fromDartWeekday(toLocalDate(iso).weekday);

String weekdayLabel(DateISO iso) => weekdayKeyOf(iso).label;

/// "YYYY-MM-DD" -> "DD/MM/YYYY".
String formatDateBR(DateISO? iso) {
  if (iso == null || iso.isEmpty) return '--/--/----';
  final p = iso.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

DateISO addDays(DateISO iso, int days) {
  final d = toLocalDate(iso);
  return toIso(DateTime(d.year, d.month, d.day + days));
}

(DateISO, DateISO) monthRange(int year, int month) =>
    (toIso(DateTime(year, month, 1)), toIso(DateTime(year, month + 1, 0)));

(DateISO, DateISO) weekRange(DateISO iso) {
  final d = toLocalDate(iso);
  final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  final sunday = DateTime(monday.year, monday.month, monday.day + 6);
  return (toIso(monday), toIso(sunday));
}

(DateISO, DateISO) yearRange(int year) => ('$year-01-01', '$year-12-31');

List<DateISO> iterDates(DateISO start, DateISO end) {
  final result = <DateISO>[];
  var current = start;
  while (current.compareTo(end) <= 0) {
    result.add(current);
    current = addDays(current, 1);
  }
  return result;
}

/// Valida "YYYY-MM-DD" como data real (rejeita 2026-02-30).
bool isValidIsoDate(String text) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (m == null) return false;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final date = DateTime(y, mo, d);
  return date.year == y && date.month == mo && date.day == d;
}
