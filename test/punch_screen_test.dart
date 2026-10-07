// Fluxo do registro de ponto com um servidor falso: sequência, toque duplicado,
// falta de conexão (não salvo x salvo) e conflito com outro aparelho/site.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubi_time/app_state.dart';
import 'package:hubi_time/core/constants.dart';
import 'package:hubi_time/core/dates.dart';
import 'package:hubi_time/data/errors.dart';
import 'package:hubi_time/data/repositories.dart';
import 'package:hubi_time/domain/models.dart';
import 'package:hubi_time/ui/screens/punch_screen.dart';
import 'package:hubi_time/ui/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _client = SupabaseClient('http://localhost:1', 'chave-de-teste', authOptions: const AuthClientOptions(autoRefreshToken: false));

WorkRecord record({String? entry, String? lunchStart, String? lunchEnd, String? exit, int version = 1, DayType type = DayType.normal, String status = 'active'}) =>
    WorkRecord(
      id: 'r1',
      workDate: todayIso(),
      entryTime: entry,
      lunchStart: lunchStart,
      lunchEnd: lunchEnd,
      exitTime: exit,
      dayType: type,
      notes: null,
      status: status,
      version: version,
    );

class FakeWork extends WorkRepository {
  FakeWork(this.stored) : super(_client);

  WorkRecord? stored;
  final calls = <String>[];
  Object? failNext; // erro a lançar na próxima gravação
  Completer<void>? gate; // segura a gravação até ser liberado
  WorkRecord? serverRecordAfterFailure; // o que existe no servidor depois de um conflito

  @override
  Future<WorkRecord?> getByDate(String userId, DateISO date) async => stored;

  @override
  Future<WorkRecord> createWithTime(String userId, DateISO date, String column, String time) async {
    calls.add('create $column=$time');
    await gate?.future;
    _throwIfFailing();
    return stored = _with(null, column, time);
  }

  @override
  Future<WorkRecord> updateTime(String id, String userId, int expectedVersion, String column, String time) async {
    calls.add('update v$expectedVersion $column=$time');
    await gate?.future;
    _throwIfFailing();
    return stored = _with(stored, column, time);
  }

  void _throwIfFailing() {
    final e = failNext;
    if (e != null) {
      failNext = null;
      if (serverRecordAfterFailure != null) stored = serverRecordAfterFailure;
      throw e;
    }
  }

  WorkRecord _with(WorkRecord? base, String column, String time) {
    final r = base ?? record();
    return WorkRecord(
      id: r.id,
      workDate: r.workDate,
      entryTime: column == 'entry_time' ? time : r.entryTime,
      lunchStart: column == 'lunch_start' ? time : r.lunchStart,
      lunchEnd: column == 'lunch_end' ? time : r.lunchEnd,
      exitTime: column == 'exit_time' ? time : r.exitTime,
      dayType: r.dayType,
      notes: r.notes,
      status: r.status,
      version: r.version + 1,
    );
  }
}

class FakeSchedule extends ScheduleRepository {
  FakeSchedule() : super(_client);
  @override
  Future<List<ScheduleEntry>> listHistory(String userId) async => [
        ScheduleEntry(id: 's', effectiveFrom: '2000-01-01', weeklyHours: {for (final d in WeekdayKey.values) d: 8.0}, standardEntryTime: null),
      ];
}

class FakeSession extends SessionController {
  FakeSession(FakeWork work) : super(_client, work: work, schedule: FakeSchedule());
  @override
  String get userId => 'u1';
}

Future<FakeWork> pumpPunch(WidgetTester tester, WorkRecord? initial) async {
  final work = FakeWork(initial);
  await tester.pumpWidget(
    AppServices(
      session: FakeSession(work),
      theme: ThemeController(null),
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: const Scaffold(body: PunchScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return work;
}

final timeRe = RegExp(r'^\d{2}:\d{2}$');

void main() {
  testWidgets('dia vazio: próxima ação é a entrada; ao registrar, avança para a saída do almoço', (tester) async {
    final work = await pumpPunch(tester, null);
    expect(find.text('Registrar entrada'), findsOneWidget);

    await tester.tap(find.text('Registrar entrada'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(work.calls, hasLength(1));
    expect(work.calls.single, startsWith('create entry_time='));
    expect(timeRe.hasMatch(work.calls.single.split('=').last), true);
    expect(find.text('Registrar saída para o almoço'), findsOneWidget);
    expect(find.textContaining('salva no servidor'), findsOneWidget);
  });

  testWidgets('dia em andamento retoma da próxima ação e envia a versão lida', (tester) async {
    final work = await pumpPunch(tester, record(entry: '08:00', lunchStart: '12:00', version: 4));
    expect(find.text('Registrar retorno do almoço'), findsOneWidget);
    await tester.tap(find.text('Registrar retorno do almoço'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(work.calls.single, startsWith('update v4 lunch_end='));
    expect(find.text('Registrar saída'), findsOneWidget);
  });

  testWidgets('toque duplicado enquanto salva envia só uma requisição', (tester) async {
    final work = await pumpPunch(tester, null);
    work.gate = Completer<void>();

    await tester.tap(find.text('Registrar entrada'));
    await tester.pump();
    // O botão está ocupado: o segundo toque não faz nada.
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(work.calls, hasLength(1));

    work.gate!.complete();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(work.calls, hasLength(1));
  });

  testWidgets('sem conexão: mostra NÃO SALVO e reenvia com o horário capturado', (tester) async {
    final work = await pumpPunch(tester, null);
    work.failNext = const OfflineException();

    await tester.tap(find.text('Registrar entrada'));
    await tester.pumpAndSettle();
    expect(find.textContaining('NÃO SALVO'), findsOneWidget);
    expect(find.textContaining('Nada foi salvo no servidor'), findsOneWidget);
    expect(work.stored, isNull);
    final capturedTime = work.calls.single.split('=').last;

    await tester.tap(find.text('Reenviar'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(work.calls, hasLength(2));
    expect(work.calls.last.split('=').last, capturedTime);
    expect(find.textContaining('NÃO SALVO'), findsNothing);
    expect(work.stored!.entryTime, capturedTime);
  });

  testWidgets('conflito com outro aparelho: recarrega, avisa e NÃO sobrescreve', (tester) async {
    final work = await pumpPunch(tester, record(entry: '08:00', version: 1));
    // Enquanto isso, o site já registrou a saída do almoço (versão 2).
    work.failNext = const ConflictException();
    work.serverRecordAfterFailure = record(entry: '08:00', lunchStart: '12:01', version: 2);

    await tester.tap(find.text('Registrar saída para o almoço'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(work.calls, hasLength(1)); // nenhuma segunda tentativa automática
    expect(work.stored!.lunchStart, '12:01'); // valor do outro lugar preservado
    expect(find.textContaining('alterado em outro lugar'), findsOneWidget);
    expect(find.text('Registrar retorno do almoço'), findsOneWidget); // tela já mostra o novo estado
  });

  testWidgets('dia criado em outro lugar entre a leitura e o toque (duplicado)', (tester) async {
    final work = await pumpPunch(tester, null);
    work.failNext = const DuplicateRecordException();
    work.serverRecordAfterFailure = record(entry: '07:58', version: 1);

    await tester.tap(find.text('Registrar entrada'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(work.stored!.entryTime, '07:58');
    expect(find.textContaining('alterado em outro lugar'), findsOneWidget);
    expect(find.text('Registrar saída para o almoço'), findsOneWidget);
  });

  testWidgets('jornada concluída não oferece novo registro', (tester) async {
    await pumpPunch(tester, record(entry: '08:00', lunchStart: '12:00', lunchEnd: '13:00', exit: '17:00'));
    expect(find.text('Jornada de hoje concluída'), findsOneWidget);
    expect(find.text('Registrar entrada'), findsNothing);
  });

  testWidgets('folga não oferece registro', (tester) async {
    await pumpPunch(tester, record(type: DayType.folga));
    expect(find.textContaining('marcado como "Folga"'), findsOneWidget);
  });

  testWidgets('registro arquivado não oferece registro', (tester) async {
    await pumpPunch(tester, record(status: 'archived'));
    expect(find.text('Registro arquivado'), findsWidgets);
  });

  testWidgets('horário inconsistente pede confirmação antes de gravar', (tester) async {
    // Entrada às 23:59: qualquer saída para o almoço "agora" (a menos que seja 23:59) fica anterior.
    final work = await pumpPunch(tester, record(entry: '23:59'));
    await tester.tap(find.text('Registrar saída para o almoço'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    if (now.hour == 23 && now.minute == 59) return; // janela de 1 minuto em que não há inconsistência
    expect(find.text('Horário inconsistente'), findsOneWidget);
    expect(work.calls, isEmpty);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(work.calls, isEmpty);

    await tester.tap(find.text('Registrar saída para o almoço'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(work.calls, hasLength(1));
  });
}
