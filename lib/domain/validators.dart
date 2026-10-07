/// Detecção de inconsistências de horário (porte de
/// hubi-time-web/src/lib/validators.ts).
library;

import '../core/formatting.dart';

class TimeWarning {
  const TimeWarning(this.field, this.message);
  final String field;
  final String message;
}

/// Sinaliza situações suspeitas sem bloquear o salvamento (igual ao site).
List<TimeWarning> detectTimeInconsistencies(
  String? entry,
  String? lunchStart,
  String? lunchEnd,
  String? exit,
) {
  final warnings = <TimeWarning>[];
  int m(String t) => timeToMinutes(t);

  if (entry != null && lunchStart != null && m(lunchStart) < m(entry)) {
    warnings.add(const TimeWarning('lunchStart', 'A saída para o almoço é anterior ao horário de entrada.'));
  }
  if (lunchStart != null && lunchEnd != null && m(lunchEnd) < m(lunchStart)) {
    warnings.add(const TimeWarning('lunchEnd', 'O retorno do almoço é anterior à saída para o almoço.'));
  }
  if (lunchEnd != null && exit != null && m(exit) < m(lunchEnd)) {
    warnings.add(const TimeWarning('exitTime', 'A saída é anterior ao retorno do almoço.'));
  }
  if (entry != null && exit != null && lunchStart == null && lunchEnd == null && m(exit) < m(entry)) {
    warnings.add(const TimeWarning('exitTime', 'A saída é anterior ao horário de entrada.'));
  }
  if (entry != null && lunchStart != null && lunchEnd != null && exit != null) {
    final total = m(exit) - m(entry) - (m(lunchEnd) - m(lunchStart));
    if (total > 16 * 60) {
      warnings.add(const TimeWarning('exitTime', 'O total de horas trabalhadas no dia parece incomum (acima de 16h).'));
    }
  }
  return warnings;
}
