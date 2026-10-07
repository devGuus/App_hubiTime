import 'package:flutter_test/flutter_test.dart';
import 'package:hubi_time/core/constants.dart';
import 'package:hubi_time/core/dates.dart';
import 'package:hubi_time/domain/punch.dart';
import 'package:hubi_time/domain/validators.dart';

void main() {
  group('nextPunchStep (sequência do dia)', () {
    test('dia vazio -> entrada', () => expect(nextPunchStep([null, null, null, null]), PunchStep.entry));
    test('entrada feita -> saída para o almoço', () => expect(nextPunchStep(['08:00', null, null, null]), PunchStep.lunchStart));
    test('almoço iniciado -> retorno', () => expect(nextPunchStep(['08:00', '12:00', null, null]), PunchStep.lunchEnd));
    test('retorno feito -> saída', () => expect(nextPunchStep(['08:00', '12:00', '13:00', null]), PunchStep.exit));
    test('dia completo -> nada', () => expect(nextPunchStep(['08:00', '12:00', '13:00', '17:00']), isNull));
    test('saída sem almoço (dia corrido): não oferece registrar almoço depois da saída', () {
      expect(nextPunchStep(['08:00', null, null, '13:00']), isNull);
    });
    test('lacuna: entrada e retorno sem saída p/ almoço -> próxima é a saída', () {
      expect(nextPunchStep(['08:00', null, '13:00', null]), PunchStep.exit);
    });
    test('folga e arquivado não têm ação', () {
      expect(nextPunchStep([null, null, null, null], dayType: DayType.folga), isNull);
      expect(nextPunchStep([null, null, null, null], archived: true), isNull);
    });
    test('colunas batem com work_records', () {
      expect(PunchStep.values.map((s) => s.column), ['entry_time', 'lunch_start', 'lunch_end', 'exit_time']);
    });
  });

  group('detectTimeInconsistencies', () {
    test('almoço antes da entrada', () {
      expect(detectTimeInconsistencies('18:00', '12:00', null, null).any((w) => w.field == 'lunchStart'), true);
    });
    test('retorno antes da saída para almoço', () {
      expect(detectTimeInconsistencies('08:00', '12:30', '11:50', null).any((w) => w.field == 'lunchEnd'), true);
    });
    test('saída antes do retorno', () {
      expect(detectTimeInconsistencies('08:00', '12:00', '13:00', '12:30').any((w) => w.field == 'exitTime'), true);
    });
    test('saída antes da entrada num dia corrido (ex.: virada de meia-noite)', () {
      expect(detectTimeInconsistencies('22:00', null, null, '02:00').any((w) => w.field == 'exitTime'), true);
    });
    test('dia completo e parcial não geram aviso', () {
      expect(detectTimeInconsistencies('08:00', '12:00', '13:00', '18:00'), isEmpty);
      expect(detectTimeInconsistencies('08:00', null, null, null), isEmpty);
    });
    test('mais de 16h trabalhadas', () {
      expect(detectTimeInconsistencies('02:00', '03:00', '03:30', '23:00'), isNotEmpty);
    });
  });

  group('datas', () {
    test('formatação e intervalos', () {
      expect(formatDateBR('2026-09-14'), '14/09/2026');
      expect(monthRange(2026, 2), ('2026-02-01', '2026-02-28'));
      expect(weekRange('2026-09-13'), ('2026-09-07', '2026-09-13')); // domingo fecha a semana
      expect(addDays('2026-12-31', 1), '2027-01-01');
      expect(iterDates('2026-09-14', '2026-09-16'), ['2026-09-14', '2026-09-15', '2026-09-16']);
    });
    test('data inexistente', () {
      expect(isValidIsoDate('2026-02-30'), false);
      expect(isValidIsoDate('2026-02-28'), true);
    });
    test('dia da semana', () => expect(weekdayLabel('2026-09-14'), 'Segunda-feira'));
  });
}
