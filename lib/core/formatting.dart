/// Formatação de horas, durações e valores (porte de formatting.ts e money.ts).
library;

import 'package:decimal/decimal.dart';

import 'dates.dart';

int timeToMinutes(String time) {
  final p = time.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

/// "HH:MM" ou "HH:MM:SS" (TIME do Postgres) -> "HH:MM".
String? trimTime(String? value) => value == null || value.isEmpty ? null : value.substring(0, 5);

String formatTimeOrPlaceholder(String? value) => trimTime(value) ?? '--:--';

String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String formatMinutesAsHours(int totalMinutes, {bool showSign = false}) {
  var sign = '';
  var minutes = totalMinutes;
  if (minutes < 0) {
    sign = '-';
    minutes = -minutes;
  } else if (showSign && minutes > 0) {
    sign = '+';
  }
  return '$sign${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}min';
}

String formatLongDate(DateISO iso) {
  final d = toLocalDate(iso);
  return '${weekdayLabel(iso)}, ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// "R$ 1.234,56" - arredonda meio-para-cima, como o site.
String formatBRL(Decimal? value) {
  if (value == null) return 'R\$ 0,00';
  final rounded = value.round(scale: 2);
  final negative = rounded < Decimal.zero;
  final parts = rounded.abs().toStringAsFixed(2).split('.');
  var remaining = parts[0];
  var grouped = '';
  while (remaining.length > 3) {
    grouped = '.${remaining.substring(remaining.length - 3)}$grouped';
    remaining = remaining.substring(0, remaining.length - 3);
  }
  return '${negative ? '-' : ''}R\$ $remaining$grouped,${parts[1]}';
}

/// Aceita "3500", "3500,00" e "3.500,00". Lança [FormatException] se inválido.
Decimal parseBRL(String text) {
  final cleaned = text.trim().replaceAll('R\$', '').trim();
  if (cleaned.isEmpty) return Decimal.zero;
  final normalized = cleaned.contains(',') ? cleaned.replaceAll('.', '').replaceAll(',', '.') : cleaned;
  final parsed = Decimal.tryParse(normalized);
  if (parsed == null) throw FormatException('Valor monetário inválido: $text');
  return parsed;
}
