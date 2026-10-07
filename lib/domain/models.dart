/// Modelos das tabelas do Supabase compartilhadas com o site
/// (hubi-time-web/src/types/database.ts). Colunas e nomes idênticos.
library;

import 'package:decimal/decimal.dart';

import '../core/constants.dart';
import '../core/dates.dart';
import '../core/formatting.dart';
import 'calculation.dart';

class WorkRecord {
  const WorkRecord({
    required this.id,
    required this.workDate,
    required this.entryTime,
    required this.lunchStart,
    required this.lunchEnd,
    required this.exitTime,
    required this.dayType,
    required this.notes,
    required this.status,
    required this.version,
  });

  factory WorkRecord.fromMap(Map<String, dynamic> m) => WorkRecord(
        id: m['id'] as String,
        workDate: m['work_date'] as String,
        entryTime: trimTime(m['entry_time'] as String?),
        lunchStart: trimTime(m['lunch_start'] as String?),
        lunchEnd: trimTime(m['lunch_end'] as String?),
        exitTime: trimTime(m['exit_time'] as String?),
        dayType: DayType.fromKey(m['day_type'] as String?),
        notes: m['notes'] as String?,
        status: m['status'] as String,
        version: (m['version'] as num).toInt(),
      );

  final String id;
  final DateISO workDate;
  final String? entryTime;
  final String? lunchStart;
  final String? lunchEnd;
  final String? exitTime;
  final DayType dayType;
  final String? notes;
  final String status;

  /// Concorrência otimista: o servidor incrementa a cada UPDATE.
  final int version;

  bool get isArchived => status == 'archived';

  /// Na ordem de [PunchStep]: entrada, saída almoço, retorno, saída.
  List<String?> get times => [entryTime, lunchStart, lunchEnd, exitTime];

  WorkRecordFields get fields => WorkRecordFields(
        workDate: workDate,
        entryTime: entryTime,
        lunchStart: lunchStart,
        lunchEnd: lunchEnd,
        exitTime: exitTime,
        dayType: dayType,
      );
}

/// Campos editáveis de um dia (mesmo payload do site).
class WorkRecordDraft {
  const WorkRecordDraft({
    this.entryTime,
    this.lunchStart,
    this.lunchEnd,
    this.exitTime,
    this.dayType = DayType.normal,
    this.notes,
  });

  final String? entryTime;
  final String? lunchStart;
  final String? lunchEnd;
  final String? exitTime;
  final DayType dayType;
  final String? notes;

  Map<String, dynamic> toMap() => {
        'entry_time': entryTime,
        'lunch_start': lunchStart,
        'lunch_end': lunchEnd,
        'exit_time': exitTime,
        'day_type': dayType.key,
        'notes': notes,
      };
}

class WorkHistoryEntry {
  const WorkHistoryEntry({
    required this.action,
    required this.fieldChanged,
    required this.oldValue,
    required this.newValue,
    required this.changedAt,
  });

  factory WorkHistoryEntry.fromMap(Map<String, dynamic> m) => WorkHistoryEntry(
        action: m['action'] as String,
        fieldChanged: m['field_changed'] as String?,
        oldValue: m['old_value'] as String?,
        newValue: m['new_value'] as String?,
        changedAt: DateTime.parse(m['changed_at'] as String).toLocal(),
      );

  final String action;
  final String? fieldChanged;
  final String? oldValue;
  final String? newValue;
  final DateTime changedAt;
}

class ScheduleEntry {
  const ScheduleEntry({
    required this.id,
    required this.effectiveFrom,
    required this.weeklyHours,
    required this.standardEntryTime,
  });

  factory ScheduleEntry.fromMap(Map<String, dynamic> m) {
    final raw = (m['weekly_hours'] as Map?) ?? const {};
    return ScheduleEntry(
      id: m['id'] as String,
      effectiveFrom: m['effective_from'] as String,
      weeklyHours: {
        for (final day in WeekdayKey.values)
          day: (raw[day.key] as num?)?.toDouble() ?? defaultWeeklyHours[day]!,
      },
      standardEntryTime: trimTime(m['standard_entry_time'] as String?),
    );
  }

  final String id;
  final DateISO effectiveFrom;
  final Map<WeekdayKey, double> weeklyHours;
  final String? standardEntryTime;

  ScheduleFields get fields => ScheduleFields(weeklyHours: weeklyHours, standardEntryTime: standardEntryTime);

  /// Vigência válida em [atDate] (a mais recente com effective_from <= atDate).
  static ScheduleEntry? pickEffective(List<ScheduleEntry> entries, DateISO atDate) {
    ScheduleEntry? best;
    for (final e in entries) {
      if (e.effectiveFrom.compareTo(atDate) <= 0 &&
          (best == null || e.effectiveFrom.compareTo(best.effectiveFrom) > 0)) {
        best = e;
      }
    }
    return best;
  }
}

Decimal _decimalOf(Object? v) => Decimal.parse(v.toString());

class SalaryEntry {
  const SalaryEntry({
    required this.id,
    required this.effectiveFrom,
    required this.salary,
    required this.monthlyHours,
  });

  factory SalaryEntry.fromMap(Map<String, dynamic> m) => SalaryEntry(
        id: m['id'] as String,
        effectiveFrom: m['effective_from'] as String,
        salary: _decimalOf(m['salary']),
        monthlyHours: _decimalOf(m['monthly_hours']),
      );

  final String id;
  final DateISO effectiveFrom;
  final Decimal salary;
  final Decimal monthlyHours;

  Decimal get hourlyRate => hourlyRateOf(salary, monthlyHours);

  static SalaryEntry? pickEffective(List<SalaryEntry> entries, DateISO atDate) {
    SalaryEntry? best;
    for (final e in entries) {
      if (e.effectiveFrom.compareTo(atDate) <= 0 &&
          (best == null || e.effectiveFrom.compareTo(best.effectiveFrom) > 0)) {
        best = e;
      }
    }
    return best;
  }
}

class OvertimeRule {
  const OvertimeRule({
    required this.id,
    required this.name,
    required this.percentage,
    required this.effectiveFrom,
  });

  factory OvertimeRule.fromMap(Map<String, dynamic> m) => OvertimeRule(
        id: m['id'] as String,
        name: m['name'] as String,
        percentage: _decimalOf(m['percentage']),
        effectiveFrom: m['effective_from'] as String,
      );

  final String id;
  final String name;
  final Decimal percentage;
  final DateISO effectiveFrom;

  static OvertimeRule? pickEffective(List<OvertimeRule> rules, DateISO atDate) {
    OvertimeRule? best;
    for (final r in rules) {
      if (r.effectiveFrom.compareTo(atDate) <= 0 &&
          (best == null || r.effectiveFrom.compareTo(best.effectiveFrom) > 0)) {
        best = r;
      }
    }
    return best;
  }
}

class Profile {
  const Profile({required this.name});
  factory Profile.fromMap(Map<String, dynamic> m) => Profile(name: (m['name'] as String?) ?? '');
  final String name;
}

class UserSettings {
  const UserSettings({required this.notificationsEnabled});

  factory UserSettings.fromMap(Map<String, dynamic> m) {
    final raw = (m['notifications_enabled'] as Map?) ?? const {};
    return UserSettings(notificationsEnabled: {
      for (final e in raw.entries)
        if (e.value is bool) e.key as String: e.value as bool,
    });
  }

  final Map<String, bool> notificationsEnabled;

  /// Ausente = ligado (mesmo padrão do site).
  bool isNotificationOn(String key) => notificationsEnabled[key] ?? true;
}

class Subscription {
  const Subscription({required this.plan, required this.currentPeriodEnd});

  factory Subscription.fromMap(Map<String, dynamic> m) =>
      Subscription(plan: m['plan'] as String, currentPeriodEnd: m['current_period_end'] as String?);

  final String plan;
  final DateISO? currentPeriodEnd;

  /// Mesma regra do site: premium enquanto hoje <= fim do período pago.
  static bool isPremium(Subscription? s, DateISO today) =>
      s?.currentPeriodEnd != null && s!.currentPeriodEnd!.compareTo(today) >= 0;
}
