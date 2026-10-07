/// Cálculos de jornada, banco de horas e horas extras.
/// Porte 1:1 de hubi-time-web/src/lib/calculation-service.ts - módulo puro,
/// sem I/O. Qualquer mudança aqui precisa ser feita também no site.
library;

import 'package:decimal/decimal.dart';

import '../core/constants.dart';
import '../core/dates.dart';
import '../core/formatting.dart';

class WorkRecordFields {
  const WorkRecordFields({
    required this.workDate,
    this.entryTime,
    this.lunchStart,
    this.lunchEnd,
    this.exitTime,
    this.dayType = DayType.normal,
  });

  final DateISO workDate;
  final String? entryTime;
  final String? lunchStart;
  final String? lunchEnd;
  final String? exitTime;
  final DayType dayType;

  WorkRecordFields withEntryTime(String entryTime) => WorkRecordFields(
        workDate: workDate,
        entryTime: entryTime,
        lunchStart: lunchStart,
        lunchEnd: lunchEnd,
        exitTime: exitTime,
        dayType: dayType,
      );
}

class ScheduleFields {
  const ScheduleFields({required this.weeklyHours, this.standardEntryTime});

  final Map<WeekdayKey, double> weeklyHours;

  /// "HH:MM". Chegada antes disso não conta como hora extra.
  final String? standardEntryTime;
}

class DayCalculation {
  const DayCalculation({
    required this.workDate,
    required this.dayType,
    required this.workedMinutes,
    required this.expectedMinutes,
    required this.breakMinutes,
    required this.isComplete,
    required this.isInProgress,
  });

  final DateISO workDate;
  final DayType dayType;
  final int workedMinutes;
  final int expectedMinutes;
  final int breakMinutes;
  final bool isComplete;
  final bool isInProgress;

  int get balanceMinutes => workedMinutes - expectedMinutes;
  int get overtimeMinutes => balanceMinutes > 0 ? balanceMinutes : 0;
}

class PeriodSummary {
  const PeriodSummary({
    required this.expectedMinutes,
    required this.workedMinutes,
    required this.workedDaysCount,
    required this.incompleteDaysCount,
    required this.days,
  });

  final int expectedMinutes;
  final int workedMinutes;
  final int workedDaysCount;
  final int incompleteDaysCount;
  final List<DayCalculation> days;

  int get balanceMinutes => workedMinutes - expectedMinutes;
  int get overtimeMinutes => days.fold(0, (t, d) => t + d.overtimeMinutes);
}

int _positive(int v) => v > 0 ? v : 0;

/// Chegada antecipada nunca conta como hora extra: recorta a entrada para o
/// padrão configurado (só nos minutos calculados, nunca no horário gravado).
WorkRecordFields _clipEarlyArrival(WorkRecordFields record, ScheduleFields? schedule) {
  final standard = schedule?.standardEntryTime;
  if (standard == null || standard.isEmpty || record.entryTime == null) return record;
  if (timeToMinutes(record.entryTime!) >= timeToMinutes(standard)) return record;
  return record.withEntryTime(standard);
}

bool isRecordComplete(WorkRecordFields r) {
  if (!r.dayType.countsAsExpectedWorkday) return true;
  return r.entryTime != null && r.lunchStart != null && r.lunchEnd != null && r.exitTime != null;
}

int computeWorkedMinutes(WorkRecordFields r) {
  var total = 0;
  final hasLunchPair = r.lunchStart != null && r.lunchEnd != null;
  if (r.entryTime != null && r.lunchStart != null) {
    total += _positive(timeToMinutes(r.lunchStart!) - timeToMinutes(r.entryTime!));
  }
  if (hasLunchPair && r.exitTime != null) {
    total += _positive(timeToMinutes(r.exitTime!) - timeToMinutes(r.lunchEnd!));
  }
  if (r.entryTime != null && r.exitTime != null && r.lunchStart == null && r.lunchEnd == null) {
    total += _positive(timeToMinutes(r.exitTime!) - timeToMinutes(r.entryTime!));
  }
  return total;
}

int computeBreakMinutes(WorkRecordFields r) {
  if (r.lunchStart != null && r.lunchEnd != null) {
    return _positive(timeToMinutes(r.lunchEnd!) - timeToMinutes(r.lunchStart!));
  }
  return 0;
}

/// Minutos trabalhados até agora, para o dia em andamento.
int computeElapsedMinutesUntilNow(WorkRecordFields r, DateTime now) {
  final current = now.hour * 60 + now.minute;
  var total = 0;
  if (r.entryTime != null && r.lunchStart != null) {
    total += _positive(timeToMinutes(r.lunchStart!) - timeToMinutes(r.entryTime!));
  } else if (r.entryTime != null && r.lunchStart == null) {
    return _positive(current - timeToMinutes(r.entryTime!));
  }
  if (r.lunchEnd != null && r.exitTime != null) {
    total += _positive(timeToMinutes(r.exitTime!) - timeToMinutes(r.lunchEnd!));
  } else if (r.lunchEnd != null && r.exitTime == null) {
    total += _positive(current - timeToMinutes(r.lunchEnd!));
  }
  return total;
}

int expectedMinutesForDay(DateISO workDate, DayType dayType, ScheduleFields? schedule) {
  if (!dayType.countsAsExpectedWorkday || schedule == null) return 0;
  final hours = schedule.weeklyHours[weekdayKeyOf(workDate)] ?? 0;
  return (hours * 60).round();
}

DayCalculation computeDay(WorkRecordFields record, ScheduleFields? schedule, [DateTime? now]) {
  final effective = _clipEarlyArrival(record, schedule);
  var worked = computeWorkedMinutes(effective);
  final expected = expectedMinutesForDay(record.workDate, record.dayType, schedule);
  final isComplete = isRecordComplete(record);
  final isInProgress = record.entryTime != null && !isComplete;

  if (now != null && record.workDate == toIso(now) && isInProgress) {
    worked = computeElapsedMinutesUntilNow(effective, now);
  }

  return DayCalculation(
    workDate: record.workDate,
    dayType: record.dayType,
    workedMinutes: worked,
    expectedMinutes: expected,
    breakMinutes: computeBreakMinutes(record),
    isComplete: isComplete,
    isInProgress: isInProgress,
  );
}

PeriodSummary summarizePeriod(List<DayCalculation> days) {
  // Dia sem jornada prevista (ex.: fim de semana) e sem registro não é "incompleto".
  final incomplete = days.where((d) =>
      d.dayType.countsAsExpectedWorkday &&
      !d.isComplete &&
      (d.expectedMinutes > 0 || d.workedMinutes > 0 || d.isInProgress));
  return PeriodSummary(
    expectedMinutes: days.fold(0, (t, d) => t + d.expectedMinutes),
    workedMinutes: days.fold(0, (t, d) => t + d.workedMinutes),
    workedDaysCount: days.where((d) => d.workedMinutes > 0).length,
    incompleteDaysCount: incomplete.length,
    days: days,
  );
}

// Piso legal de hora extra (CLT): 50% em dia útil, 100% em domingo/feriado.
final _legalWeekday = Decimal.fromInt(50);
final _legalSundayOrHoliday = Decimal.fromInt(100);
final _hundred = Decimal.fromInt(100);
final _sixty = Decimal.fromInt(60);

/// Percentual efetivo de hora extra do dia: nunca abaixo do piso legal; a
/// regra cadastrada só vale quando é mais vantajosa.
Decimal effectiveOvertimePercentage(DateISO workDate, DayType dayType, Decimal? customPercentage) {
  final sundayOrHoliday = dayType == DayType.feriado || weekdayKeyOf(workDate) == WeekdayKey.domingo;
  final legal = sundayOrHoliday ? _legalSundayOrHoliday : _legalWeekday;
  if (customPercentage == null) return legal;
  return customPercentage > legal ? customPercentage : legal;
}

Decimal _divide(Decimal a, Decimal b) => (a / b).toDecimal(scaleOnInfinitePrecision: 20);

Decimal overtimeValue(int overtimeMinutes, Decimal hourlyRate, Decimal? percentage) {
  if (overtimeMinutes <= 0) return Decimal.zero.round(scale: 2);
  final multiplier = percentage == null ? Decimal.one : Decimal.one + _divide(percentage, _hundred);
  final hours = _divide(Decimal.fromInt(overtimeMinutes), _sixty);
  return (hours * hourlyRate * multiplier).round(scale: 2);
}

/// Soma o valor de hora extra dia a dia, aplicando o piso legal de cada dia.
Decimal overtimeValueForPeriod(List<DayCalculation> days, Decimal hourlyRate, Decimal? customPercentage) {
  var total = Decimal.zero;
  for (final day in days) {
    final minutes = day.overtimeMinutes;
    if (minutes <= 0) continue;
    final pct = effectiveOvertimePercentage(day.workDate, day.dayType, customPercentage);
    total += overtimeValue(minutes, hourlyRate, pct);
  }
  return total.round(scale: 2);
}

Decimal regularHoursValue(int workedMinutes, int overtimeMinutes, Decimal hourlyRate) {
  final regular = _positive(workedMinutes - overtimeMinutes);
  return (_divide(Decimal.fromInt(regular), _sixty) * hourlyRate).round(scale: 2);
}

/// Valor da hora = salário / divisor mensal, 2 casas (mesmo arredondamento do site).
Decimal hourlyRateOf(Decimal salary, Decimal monthlyHours) {
  if (monthlyHours <= Decimal.zero) return Decimal.zero;
  return _divide(salary, monthlyHours).round(scale: 2);
}

/// Divisor mensal sugerido: horas semanais x 5 (44h -> 220).
int monthlyHoursDivisorFor(Map<WeekdayKey, double> weeklyHours) =>
    (weeklyHours.values.fold(0.0, (s, h) => s + h) * 5).round();
