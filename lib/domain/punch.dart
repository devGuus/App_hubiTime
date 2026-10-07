/// Sequência de registros do dia.
///
/// O site não tem um fluxo de "bater ponto": o dia é um editor dos 4 horários.
/// A "próxima ação" é derivada aqui: o primeiro horário vazio DEPOIS do último
/// preenchido, na ordem entrada -> saída almoço -> retorno -> saída. Se a saída
/// já está preenchida (ou o dia não é "normal"), não há próxima ação.
library;

import '../core/constants.dart';

enum PunchStep {
  entry('entry_time', 'Entrada no trabalho', 'Registrar entrada'),
  lunchStart('lunch_start', 'Saída para o almoço', 'Registrar saída para o almoço'),
  lunchEnd('lunch_end', 'Retorno do almoço', 'Registrar retorno do almoço'),
  exit('exit_time', 'Saída do trabalho', 'Registrar saída');

  const PunchStep(this.column, this.label, this.actionLabel);

  /// Coluna em work_records.
  final String column;
  final String label;
  final String actionLabel;
}

/// [times] segue a ordem de [PunchStep.values]; vazio = null.
PunchStep? nextPunchStep(List<String?> times, {DayType dayType = DayType.normal, bool archived = false}) {
  if (archived || !dayType.countsAsExpectedWorkday) return null;
  final next = times.lastIndexWhere((t) => t != null) + 1;
  return next < PunchStep.values.length ? PunchStep.values[next] : null;
}
