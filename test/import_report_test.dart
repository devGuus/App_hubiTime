import 'dart:convert';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubi_time/core/constants.dart';
import 'package:hubi_time/domain/import_parser.dart';
import 'package:hubi_time/domain/import_plan.dart';
import 'package:hubi_time/domain/models.dart';
import 'package:hubi_time/domain/report.dart';
import 'package:hubi_time/data/exporter.dart';

Uint8List csv(String text) => Uint8List.fromList(utf8.encode(text));

WorkRecord record(String date, {String? entry, String? lunchStart, String? lunchEnd, String? exit, String status = 'active'}) =>
    WorkRecord(
      id: 'id-$date',
      workDate: date,
      entryTime: entry,
      lunchStart: lunchStart,
      lunchEnd: lunchEnd,
      exitTime: exit,
      dayType: DayType.normal,
      notes: null,
      status: status,
      version: 3,
    );

void main() {
  const header = 'Data;Entrada;Saida almoco;Retorno;Saida;Tipo de dia;Observacoes';

  group('importação - CSV', () {
    test('linha válida (DD/MM/AAAA e ISO)', () {
      final rows = parseImportFile('a.csv', csv('$header\n01/03/2026;08:00;12:00;13:00;17:00;Dia normal;ok\n2026-03-02;8:05;;;;Folga;'));
      expect(rows, hasLength(2));
      expect(rows[0].errors, isEmpty);
      expect(rows[0].workDate, '2026-03-01');
      expect(rows[0].entryTime, '08:00');
      expect(rows[0].notes, 'ok');
      expect(rows[1].workDate, '2026-03-02');
      expect(rows[1].entryTime, '08:05');
      expect(rows[1].dayType, DayType.folga);
    });

    test('tipo de dia aceita rótulo com acento, sem acento e a chave', () {
      final rows = parseImportFile('a.csv', csv('$header\n01/03/2026;;;;;Férias;\n02/03/2026;;;;;ferias;\n03/03/2026;;;;;ausencia;'));
      expect(rows.map((r) => r.dayType), [DayType.ferias, DayType.ferias, DayType.ausencia]);
      expect(rows.every((r) => r.errors.isEmpty), true);
    });

    test('erros claros por linha: data, hora e tipo desconhecidos', () {
      final rows = parseImportFile('a.csv', csv('$header\n31/02/2026;08:00;;;;;\nxx;;;;;;\n01/03/2026;25:00;;;;;\n02/03/2026;;;;;;;\n03/03/2026;;;;;Banana;'));
      expect(rows[0].errors.single, contains('não existe'));
      expect(rows[1].errors.single, contains('formato inválido'));
      expect(rows[2].errors.single, contains('horário inválido'));
      expect(rows[3].errors, isEmpty);
      expect(rows[4].errors.single, contains('desconhecido'));
    });

    test('data obrigatória', () {
      final rows = parseImportFile('a.csv', csv('$header\n;08:00;;;;;'));
      expect(rows.single.errors.single, 'Data: campo obrigatório.');
    });

    test('data repetida no arquivo marca a segunda ocorrência', () {
      final rows = parseImportFile('a.csv', csv('$header\n01/03/2026;08:00;;;;;\n01/03/2026;09:00;;;;;'));
      expect(rows[0].errors, isEmpty);
      expect(rows[1].errors.single, contains('repetida'));
    });

    test('inconsistência de horário vira aviso, não erro', () {
      final rows = parseImportFile('a.csv', csv('$header\n01/03/2026;08:00;07:00;;;;'));
      expect(rows.single.errors, isEmpty);
      expect(rows.single.warnings, isNotEmpty);
    });

    test('aspas, BOM e vírgula como separador', () {
      final rows = parseImportFile('a.txt', csv('﻿Data,Entrada,Observacoes\n01/03/2026,08:00,"viagem, cliente"'));
      expect(rows.single.entryTime, '08:00');
      expect(rows.single.notes, 'viagem, cliente');
    });

    test('sem a coluna Data', () {
      expect(() => parseImportFile('a.csv', csv('Dia;Entrada\n01/03/2026;08:00')), throwsA(isA<ImportFileException>()));
    });

    test('extensão inválida, vazio e grande demais', () {
      expect(() => parseImportFile('a.pdf', csv('x')), throwsA(isA<ImportFileException>()));
      expect(() => parseImportFile('a.csv', Uint8List(0)), throwsA(isA<ImportFileException>()));
      expect(() => parseImportFile('a.csv', Uint8List(maxImportFileBytes + 1)), throwsA(isA<ImportFileException>()));
    });

    test('limite de linhas', () {
      final lines = [header, for (var i = 0; i < maxImportRows + 1; i++) '01/03/2026;;;;;;'].join('\n');
      expect(() => parseImportFile('a.csv', csv(lines)), throwsA(isA<ImportFileException>()));
    });

    test('modelo CSV do app é lido sem erros (round trip)', () {
      final rows = parseImportFile('modelo.csv', csv(importTemplateCsv()));
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.errors.isEmpty), true);
      expect(rows[1].dayType, DayType.folga);
    });
  });

  group('importação - XLSX', () {
    test('modelo XLSX do app é lido sem erros (round trip)', () {
      final rows = parseImportFile('modelo.xlsx', Uint8List.fromList(importTemplateXlsx()));
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.errors.isEmpty), true);
      expect(rows[0].workDate, '2026-03-01');
      expect(rows[0].exitTime, '17:00');
    });

    test('arquivo corrompido', () {
      expect(() => parseImportFile('a.xlsx', csv('isto não é um xlsx')), throwsA(isA<ImportFileException>()));
    });
  });

  group('classificação (novo / já existe / erro)', () {
    test('classifica frente ao que existe no servidor', () {
      final parsed = parseImportFile('a.csv', csv('$header\n01/03/2026;08:00;;;;;\n02/03/2026;08:00;;;;;\nxx;;;;;;'));
      final rows = classifyRows(parsed, {'2026-03-02': record('2026-03-02', entry: '07:00')});
      expect(rows.map((r) => r.status), [ImportStatus.novo, ImportStatus.conflito, ImportStatus.erro]);
      expect(rows[1].existing!.version, 3);
      expect(rows[1].overwrite, false); // nunca sobrescreve sem o usuário pedir
    });

    test('intervalo de datas', () {
      final parsed = parseImportFile('a.csv', csv('$header\n05/03/2026;;;;;;\n01/03/2026;;;;;;\nxx;;;;;;'));
      expect(dateSpan(parsed), ('2026-03-01', '2026-03-05'));
    });
  });

  group('relatórios', () {
    final monday = '2026-09-14';
    final schedules = [
      ScheduleEntry(id: 's', effectiveFrom: '2026-01-01', weeklyHours: defaultWeeklyHours, standardEntryTime: null),
    ];
    final records = {
      monday: record(monday, entry: '08:00', lunchStart: '12:00', lunchEnd: '13:00', exit: '18:00'), // +1h
    };

    test('jornada: colunas escolhidas + Data sempre presente', () {
      final days = calculateDays(start: monday, end: '2026-09-15', recordsByDate: records, schedules: schedules);
      final t = buildWorkReport(days: days, recordsByDate: records, selectedColumns: {'Entrada', 'Horas extras'});
      expect(t.headers, ['Data', 'Entrada', 'Horas extras']);
      expect(t.rows, hasLength(2));
      expect(t.rows[0]['Data'], '14/09/2026');
      expect(t.rows[0]['Entrada'], '08:00');
      expect(t.rows[0]['Horas extras'], '1h 00min');
      expect(t.rows[1]['Entrada'], '--:--');
    });

    test('jornada: situação e saldo', () {
      final days = calculateDays(start: monday, end: '2026-09-15', recordsByDate: records, schedules: schedules);
      final t = buildWorkReport(days: days, recordsByDate: records, selectedColumns: {...allToggleableColumns});
      expect(t.headers, workReportHeaders);
      expect(t.rows[0]['Situacao'], 'Completo');
      expect(t.rows[0]['Saldo (h)'], '+1h 00min');
      expect(t.rows[1]['Situacao'], 'Incompleto');
      expect(t.rows[1]['Saldo (h)'], '-8h 00min');
    });

    test('financeiro: 1h extra a R\$ 20/h com piso de 50% de uma segunda', () {
      final days = calculateDays(start: monday, end: monday, recordsByDate: records, schedules: schedules);
      final t = buildFinanceReport(
        start: monday,
        end: monday,
        days: days,
        salaryHistory: [SalaryEntry(id: 'x', effectiveFrom: '2026-01-01', salary: Decimal.parse('4400'), monthlyHours: Decimal.fromInt(220))],
        overtimeRules: const [],
      );
      expect(t.headers, financeReportHeaders);
      final row = t.rows.single;
      expect(row['Periodo'], '14/09/2026 a 14/09/2026');
      expect(row['Valor hora'], 'R\$ 20,00');
      expect(row['Horas extras'], '1h 00min');
      expect(row['Valor extra'], 'R\$ 30,00');
      expect(row['Valor normal'], 'R\$ 160,00');
      expect(row['Total estimado'], 'R\$ 190,00');
    });

    test('financeiro sem salário cadastrado zera os valores', () {
      final days = calculateDays(start: monday, end: monday, recordsByDate: records, schedules: schedules);
      final t = buildFinanceReport(start: monday, end: monday, days: days, salaryHistory: const [], overtimeRules: const []);
      expect(t.rows.single['Total estimado'], 'R\$ 0,00');
    });

    test('filtros de período', () {
      final now = DateTime(2026, 9, 16); // quarta
      expect(rangeForOption(PeriodOption.today, '', '', now), ('2026-09-16', '2026-09-16'));
      expect(rangeForOption(PeriodOption.week, '', '', now), ('2026-09-14', '2026-09-20'));
      expect(rangeForOption(PeriodOption.month, '', '', now), ('2026-09-01', '2026-09-30'));
      expect(rangeForOption(PeriodOption.year, '', '', now), ('2026-01-01', '2026-12-31'));
      expect(rangeForOption(PeriodOption.custom, '2026-09-20', '2026-09-10', now), ('2026-09-10', '2026-09-20'));
    });
  });

  group('exportação', () {
    final table = ReportTable(title: 'Relatorio de Jornada', headers: const ['Data', 'Observacoes'], rows: const [
      {'Data': '14/09/2026', 'Observacoes': 'a;b'},
    ]);

    test('CSV: BOM, ";" e célula com ";" vira ","', () {
      final bytes = buildCsv(table);
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.sublist(3)), 'Data;Observacoes\r\n14/09/2026;a,b');
    });

    test('XLSX gerado é um zip legível pelo próprio importador de planilhas', () {
      final bytes = buildXlsx(table);
      expect(bytes.sublist(0, 2), [0x50, 0x4B]); // "PK"
    });

    test('PDF gerado', () async {
      final bytes = await buildPdf(table);
      expect(utf8.decode(bytes.sublist(0, 4)), '%PDF');
    });
  });
}
