// Porte dos casos de hubi-time-web/src/lib/calculation-service.test.ts:
// o app precisa dar exatamente os mesmos números que o site.
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubi_time/core/constants.dart';
import 'package:hubi_time/core/formatting.dart';
import 'package:hubi_time/domain/calculation.dart';

WorkRecordFields rec({
  String date = '2026-09-14', // segunda-feira
  String? entry,
  String? lunchStart,
  String? lunchEnd,
  String? exit,
  DayType type = DayType.normal,
}) =>
    WorkRecordFields(workDate: date, entryTime: entry, lunchStart: lunchStart, lunchEnd: lunchEnd, exitTime: exit, dayType: type);

ScheduleFields schedule([Map<WeekdayKey, double> overrides = const {}, String? standardEntry]) =>
    ScheduleFields(weeklyHours: {...defaultWeeklyHours, ...overrides}, standardEntryTime: standardEntry);

DayCalculation day(String date, int balance, {DayType type = DayType.normal}) => DayCalculation(
      workDate: date,
      dayType: type,
      workedMinutes: balance > 0 ? balance : 0,
      expectedMinutes: balance > 0 ? 0 : -balance,
      breakMinutes: 0,
      isComplete: true,
      isInProgress: false,
    );

void main() {
  group('computeWorkedMinutes', () {
    test('dia completo', () {
      expect(computeWorkedMinutes(rec(entry: '08:00', lunchStart: '12:00', lunchEnd: '13:00', exit: '18:00')), 9 * 60);
    });
    test('sem almoço usa entrada->saída', () {
      expect(computeWorkedMinutes(rec(entry: '09:00', exit: '13:00')), 4 * 60);
    });
    test('só entrada conta zero', () => expect(computeWorkedMinutes(rec(entry: '08:00')), 0));
    test('registro vazio conta zero', () => expect(computeWorkedMinutes(rec()), 0));
    test('saída antes da entrada não gera minutos negativos (virada de dia não é suportada, como no site)', () {
      expect(computeWorkedMinutes(rec(entry: '22:00', exit: '02:00')), 0);
    });
  });

  group('intervalo e andamento', () {
    test('intervalo com os dois horários', () => expect(computeBreakMinutes(rec(lunchStart: '12:00', lunchEnd: '13:15')), 75));
    test('intervalo incompleto é zero', () => expect(computeBreakMinutes(rec(lunchStart: '12:00')), 0));
    test('antes do almoço', () {
      expect(computeElapsedMinutesUntilNow(rec(entry: '08:00'), DateTime(2026, 9, 14, 10, 30)), 150);
    });
    test('depois do retorno do almoço', () {
      expect(computeElapsedMinutesUntilNow(rec(entry: '08:00', lunchStart: '12:00', lunchEnd: '13:00'), DateTime(2026, 9, 14, 15)), 6 * 60);
    });
  });

  group('expectedMinutesForDay', () {
    test('dia normal usa a carga', () => expect(expectedMinutesForDay('2026-09-14', DayType.normal, schedule()), 480));
    test('folga é zero', () => expect(expectedMinutesForDay('2026-09-14', DayType.folga, schedule()), 0));
    test('sem carga é zero', () => expect(expectedMinutesForDay('2026-09-14', DayType.normal, null), 0));
    test('sábado usa a chave sabado', () => expect(expectedMinutesForDay('2026-09-19', DayType.normal, schedule({WeekdayKey.sabado: 4})), 240));
    test('domingo usa a chave domingo', () => expect(expectedMinutesForDay('2026-09-13', DayType.normal, schedule({WeekdayKey.domingo: 2})), 120));
  });

  group('completude', () {
    test('normal sem os 4 horários é incompleto', () => expect(isRecordComplete(rec(entry: '08:00')), false));
    test('folga é completa', () => expect(isRecordComplete(rec(type: DayType.folga)), true));
    test('4 horários = completo', () => expect(isRecordComplete(rec(entry: '08:00', lunchStart: '12:00', lunchEnd: '13:00', exit: '17:00')), true));
  });

  group('período', () {
    test('totais e contagens', () {
      final sch = schedule();
      final days = [
        computeDay(rec(entry: '08:00', lunchStart: '12:00', lunchEnd: '13:00', exit: '17:00'), sch),
        computeDay(rec(date: '2026-09-15'), sch),
      ];
      final s = summarizePeriod(days);
      expect(s.workedMinutes, 8 * 60);
      expect(s.expectedMinutes, 16 * 60);
      expect(s.balanceMinutes, -8 * 60);
      expect(s.workedDaysCount, 1);
      expect(s.incompleteDaysCount, 1);
    });
    test('sábado sem registro não é incompleto', () {
      expect(summarizePeriod([computeDay(rec(date: '2026-09-19'), schedule())]).incompleteDaysCount, 0);
    });
    test('saldo por dia (+14, -7, +41)', () {
      final sch = schedule();
      int bal(String d, String exit) =>
          computeDay(rec(date: d, entry: '08:00', lunchStart: '12:00', lunchEnd: '13:00', exit: exit), sch).balanceMinutes;
      expect([bal('2026-09-14', '17:14'), bal('2026-09-15', '16:53'), bal('2026-09-16', '17:41')], [14, -7, 41]);
    });
  });

  group('horas extras e salário', () {
    test('multiplicador da regra', () => expect(overtimeValue(60, Decimal.parse('20.00'), Decimal.fromInt(50)), Decimal.fromInt(30)));
    test('sem regra usa o valor normal', () => expect(overtimeValue(60, Decimal.parse('20.00'), null), Decimal.fromInt(20)));
    test('zero minutos = zero', () => expect(overtimeValue(0, Decimal.parse('20.00'), null), Decimal.zero));
    test('horas normais excluem as extras', () => expect(regularHoursValue(540, 60, Decimal.parse('10.00')), Decimal.fromInt(80)));
    test('valor-hora = salário / divisor, 2 casas', () {
      expect(hourlyRateOf(Decimal.parse('3500'), Decimal.fromInt(220)), Decimal.parse('15.91'));
      expect(hourlyRateOf(Decimal.parse('3500'), Decimal.zero), Decimal.zero);
    });
    test('divisor sugerido: 36h semanais -> 180', () => expect(monthlyHoursDivisorFor(defaultWeeklyHours.map((k, v) => MapEntry(k, k == WeekdayKey.sexta ? 4.0 : v))), 180));
    test('divisor sugerido da jornada padrão (40h) -> 200', () => expect(monthlyHoursDivisorFor(defaultWeeklyHours), 200));
  });

  group('chegada antecipada', () {
    WorkRecordFields full(String entry) => rec(entry: entry, lunchStart: '12:00', lunchEnd: '13:00', exit: '17:00');
    test('chegar antes não gera hora extra', () {
      final d = computeDay(full('07:40'), schedule({}, '08:00'));
      expect(d.workedMinutes, 480);
      expect(d.balanceMinutes, 0);
    });
    test('chegar depois não é afetado', () => expect(computeDay(full('08:10'), schedule({}, '08:00')).workedMinutes, 470));
    test('sem entrada padrão, a chegada antecipada conta', () => expect(computeDay(full('07:40'), schedule()).workedMinutes, 500));
  });

  group('piso legal de hora extra', () {
    test('dia normal: 50%', () => expect(effectiveOvertimePercentage('2026-09-14', DayType.normal, null), Decimal.fromInt(50)));
    test('domingo: 100%', () => expect(effectiveOvertimePercentage('2026-09-13', DayType.normal, null), Decimal.fromInt(100)));
    test('feriado em dia útil: 100%', () => expect(effectiveOvertimePercentage('2026-09-14', DayType.feriado, null), Decimal.fromInt(100)));
    test('regra abaixo do piso é ignorada', () => expect(effectiveOvertimePercentage('2026-09-14', DayType.normal, Decimal.fromInt(30)), Decimal.fromInt(50)));
    test('regra acima do piso prevalece', () => expect(effectiveOvertimePercentage('2026-09-14', DayType.normal, Decimal.fromInt(70)), Decimal.fromInt(70)));
    test('regra de 50% não reduz o piso do domingo', () => expect(effectiveOvertimePercentage('2026-09-13', DayType.normal, Decimal.fromInt(50)), Decimal.fromInt(100)));
    test('período: 1h segunda (150%) + 1h domingo (200%) a R\$10 = R\$35', () {
      final v = overtimeValueForPeriod([day('2026-09-14', 60), day('2026-09-13', 60)], Decimal.parse('10.00'), null);
      expect(v, Decimal.fromInt(35));
    });
    test('saldo negativo não entra', () => expect(overtimeValueForPeriod([day('2026-09-14', -30)], Decimal.parse('10.00'), null), Decimal.zero));
  });

  group('formatação', () {
    test('minutos como horas', () {
      expect(formatMinutesAsHours(125), '2h 05min');
      expect(formatMinutesAsHours(-90, showSign: true), '-1h 30min');
      expect(formatMinutesAsHours(30, showSign: true), '+0h 30min');
    });
    test('BRL', () {
      expect(formatBRL(Decimal.parse('1234.5')), 'R\$ 1.234,50');
      expect(formatBRL(Decimal.parse('-0.005')), '-R\$ 0,01');
      expect(formatBRL(null), 'R\$ 0,00');
    });
    test('parseBRL', () {
      expect(parseBRL('R\$ 3.500,50'), Decimal.parse('3500.50'));
      expect(parseBRL('3500'), Decimal.fromInt(3500));
      expect(() => parseBRL('abc'), throwsFormatException);
    });
  });
}
