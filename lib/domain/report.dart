/// Montagem das linhas dos relatórios exportáveis. Porte de
/// hubi-time-web/src/app/(app)/relatorios/page.tsx + report-service.ts:
/// mesmos cabeçalhos, colunas, textos e cálculos.
library;

import 'package:decimal/decimal.dart';

import '../core/constants.dart';
import '../core/dates.dart';
import '../core/formatting.dart';
import 'calculation.dart';
import 'models.dart';

enum ReportType { work, finance }

enum ExportFormat {
  xlsx('Excel', 'Planilha .xlsx formatada'),
  csv('CSV', 'Dados brutos, separados por ponto e vírgula'),
  pdf('PDF', 'Pronto para impressão');

  const ExportFormat(this.label, this.description);
  final String label;
  final String description;
}

/// Os cabeçalhos são o contrato com o importador e com o site - não traduzir.
const workReportHeaders = [
  'Data', 'Dia da semana', 'Entrada', 'Saida almoco', 'Retorno', 'Saida',
  'Horas trabalhadas', 'Horas previstas', 'Saldo (h)', 'Horas extras',
  'Tipo de dia', 'Observacoes', 'Situacao',
];

const financeReportHeaders = [
  'Periodo', 'Horas normais', 'Horas extras', 'Valor hora', 'Valor normal', 'Valor extra', 'Total estimado',
];

/// "Data" sempre vai no arquivo; as demais colunas o usuário escolhe.
const mandatoryColumn = 'Data';

class ReportColumn {
  const ReportColumn(this.key, this.label);
  final String key;
  final String label;
}

const workColumnGroups = <(String, List<ReportColumn>)>[
  ('Horários do dia', [
    ReportColumn('Entrada', 'Entrada'),
    ReportColumn('Saida almoco', 'Saída p/ almoço'),
    ReportColumn('Retorno', 'Retorno do almoço'),
    ReportColumn('Saida', 'Saída'),
  ]),
  ('Totais calculados', [
    ReportColumn('Horas trabalhadas', 'Horas trabalhadas'),
    ReportColumn('Horas previstas', 'Horas previstas'),
    ReportColumn('Saldo (h)', 'Saldo de horas'),
    ReportColumn('Horas extras', 'Horas extras'),
  ]),
  ('Outras informações', [
    ReportColumn('Dia da semana', 'Dia da semana'),
    ReportColumn('Tipo de dia', 'Tipo de dia'),
    ReportColumn('Observacoes', 'Observações'),
    ReportColumn('Situacao', 'Situação'),
  ]),
];

final allToggleableColumns = [for (final g in workColumnGroups) for (final c in g.$2) c.key];

class ReportTable {
  const ReportTable({required this.title, required this.headers, required this.rows});
  final String title;
  final List<String> headers;
  final List<Map<String, String>> rows;
}

List<DayCalculation> calculateDays({
  required DateISO start,
  required DateISO end,
  required Map<DateISO, WorkRecord> recordsByDate,
  required List<ScheduleEntry> schedules,
}) {
  return iterDates(start, end).map((date) {
    final record = recordsByDate[date];
    final schedule = ScheduleEntry.pickEffective(schedules, date);
    return computeDay(
      WorkRecordFields(
        workDate: date,
        entryTime: record?.entryTime,
        lunchStart: record?.lunchStart,
        lunchEnd: record?.lunchEnd,
        exitTime: record?.exitTime,
        dayType: record?.dayType ?? DayType.normal,
      ),
      schedule?.fields,
    );
  }).toList();
}

ReportTable buildWorkReport({
  required List<DayCalculation> days,
  required Map<DateISO, WorkRecord> recordsByDate,
  required Set<String> selectedColumns,
}) {
  final headers = workReportHeaders.where((h) => h == mandatoryColumn || selectedColumns.contains(h)).toList();
  final rows = days.map((day) {
    final record = recordsByDate[day.workDate];
    return {
      'Data': formatDateBR(day.workDate),
      'Dia da semana': weekdayLabel(day.workDate),
      'Entrada': formatTimeOrPlaceholder(record?.entryTime),
      'Saida almoco': formatTimeOrPlaceholder(record?.lunchStart),
      'Retorno': formatTimeOrPlaceholder(record?.lunchEnd),
      'Saida': formatTimeOrPlaceholder(record?.exitTime),
      'Horas trabalhadas': formatMinutesAsHours(day.workedMinutes),
      'Horas previstas': formatMinutesAsHours(day.expectedMinutes),
      'Saldo (h)': formatMinutesAsHours(day.balanceMinutes, showSign: true),
      'Horas extras': formatMinutesAsHours(day.overtimeMinutes),
      'Tipo de dia': day.dayType.label,
      'Observacoes': record?.notes ?? '',
      'Situacao': day.isComplete ? 'Completo' : 'Incompleto',
    };
  }).toList();
  return ReportTable(title: 'Relatorio de Jornada', headers: headers, rows: rows);
}

/// Resumo financeiro do período: um valor-hora vigente no fim do período
/// (igual ao site), com o piso legal de hora extra aplicado dia a dia.
ReportTable buildFinanceReport({
  required DateISO start,
  required DateISO end,
  required List<DayCalculation> days,
  required List<SalaryEntry> salaryHistory,
  required List<OvertimeRule> overtimeRules,
}) {
  final salary = SalaryEntry.pickEffective(salaryHistory, end);
  final rate = salary?.hourlyRate ?? Decimal.zero;
  final rule = OvertimeRule.pickEffective(overtimeRules, end);
  final summary = summarizePeriod(days);
  final overtimeMinutes = summary.overtimeMinutes;
  final overtime = overtimeValueForPeriod(days, rate, rule?.percentage);
  final regular = regularHoursValue(summary.workedMinutes, overtimeMinutes, rate);
  return ReportTable(
    title: 'Relatorio Financeiro (estimativa)',
    headers: financeReportHeaders,
    rows: [
      {
        'Periodo': '${formatDateBR(start)} a ${formatDateBR(end)}',
        'Horas normais': formatMinutesAsHours(summary.workedMinutes - overtimeMinutes),
        'Horas extras': formatMinutesAsHours(overtimeMinutes),
        'Valor hora': formatBRL(rate),
        'Valor normal': formatBRL(regular),
        'Valor extra': formatBRL(overtime),
        'Total estimado': formatBRL(regular + overtime),
      },
    ],
  );
}

enum PeriodOption {
  today('Hoje'),
  week('Semana'),
  month('Mês'),
  year('Ano'),
  custom('Intervalo personalizado');

  const PeriodOption(this.label);
  final String label;
}

(DateISO, DateISO) rangeForOption(PeriodOption option, DateISO customStart, DateISO customEnd, [DateTime? now]) {
  final today = todayIso(now);
  switch (option) {
    case PeriodOption.today:
      return (today, today);
    case PeriodOption.week:
      return weekRange(today);
    case PeriodOption.month:
      final p = today.split('-').map(int.parse).toList();
      return monthRange(p[0], p[1]);
    case PeriodOption.year:
      return yearRange(int.parse(today.substring(0, 4)));
    case PeriodOption.custom:
      return customStart.compareTo(customEnd) <= 0 ? (customStart, customEnd) : (customEnd, customStart);
  }
}
