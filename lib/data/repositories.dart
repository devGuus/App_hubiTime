/// Acesso às tabelas do Supabase. Mesmas tabelas, colunas e filtros dos
/// repositórios do site (hubi-time-web/src/lib/repositories). Toda consulta
/// usa a sessão do usuário (chave anon) e filtra por user_id além do RLS.
library;

import 'package:decimal/decimal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../core/dates.dart';
import '../domain/models.dart';
import 'errors.dart';

class WorkRepository {
  const WorkRepository(this._client);
  final SupabaseClient _client;

  Future<WorkRecord?> getByDate(String userId, DateISO date) => guard('buscar o registro do dia', () async {
        final row = await _client
            .from('work_records')
            .select()
            .eq('user_id', userId)
            .eq('work_date', date)
            .limit(1)
            .maybeSingle();
        return row == null ? null : WorkRecord.fromMap(row);
      });

  Future<List<WorkRecord>> listByRange(String userId, DateISO start, DateISO end, {bool includeArchived = false}) =>
      guard('listar os registros do período', () async {
        var query = _client
            .from('work_records')
            .select()
            .eq('user_id', userId)
            .gte('work_date', start)
            .lte('work_date', end);
        if (!includeArchived) query = query.eq('status', 'active');
        final rows = await query.order('work_date', ascending: true);
        return rows.map(WorkRecord.fromMap).toList();
      });

  /// Cria o registro do dia já com um único horário (primeira batida do dia).
  Future<WorkRecord> createWithTime(String userId, DateISO date, String column, String time) =>
      guard('criar o registro do dia', () async {
        final row = await _client
            .from('work_records')
            .insert({'user_id': userId, 'work_date': date, 'day_type': DayType.normal.key, column: time})
            .select()
            .single();
        return WorkRecord.fromMap(row);
      });

  Future<WorkRecord> create(String userId, DateISO date, WorkRecordDraft draft) =>
      guard('criar o registro', () async {
        final row = await _client
            .from('work_records')
            .insert({'user_id': userId, 'work_date': date, ...draft.toMap()})
            .select()
            .single();
        return WorkRecord.fromMap(row);
      });

  /// Insere vários dias novos numa única requisição (tudo ou nada). Usado só
  /// pela importação; se falhar, o chamador reenvia linha a linha.
  Future<void> createMany(String userId, List<(DateISO, WorkRecordDraft)> rows) =>
      guard('importar os registros', () async {
        await _client
            .from('work_records')
            .insert([for (final (date, draft) in rows) {'user_id': userId, 'work_date': date, ...draft.toMap()}]);
      });

  /// UPDATE com concorrência otimista: só aplica se `version` ainda é a lida.
  /// Se outro lugar mudou o registro, lança [ConflictException].
  Future<WorkRecord> _updateVersioned(String id, String userId, int expectedVersion, Map<String, dynamic> fields) =>
      guard('atualizar o registro', () async {
        final row = await _client
            .from('work_records')
            .update(fields)
            .eq('id', id)
            .eq('user_id', userId)
            .eq('version', expectedVersion)
            .select()
            .maybeSingle();
        if (row == null) throw const ConflictException();
        return WorkRecord.fromMap(row);
      });

  Future<WorkRecord> update(String id, String userId, int expectedVersion, WorkRecordDraft draft) =>
      _updateVersioned(id, userId, expectedVersion, draft.toMap());

  /// Grava só um horário (batida), sem tocar nos outros campos.
  Future<WorkRecord> updateTime(String id, String userId, int expectedVersion, String column, String time) =>
      _updateVersioned(id, userId, expectedVersion, {column: time});

  Future<WorkRecord> archive(String id, String userId) => guard('arquivar o registro', () async {
        final row = await _client
            .from('work_records')
            .update({'status': 'archived', 'archived_at': DateTime.now().toUtc().toIso8601String(), 'archived_by': userId})
            .eq('id', id)
            .eq('user_id', userId)
            .select()
            .maybeSingle();
        if (row == null) throw const AppException('Registro não encontrado para arquivar.');
        return WorkRecord.fromMap(row);
      });

  Future<WorkRecord> restore(String id, String userId) => guard('restaurar o registro', () async {
        final row = await _client
            .from('work_records')
            .update({'status': 'active', 'archived_at': null, 'archived_by': null})
            .eq('id', id)
            .eq('user_id', userId)
            .select()
            .maybeSingle();
        if (row == null) throw const AppException('Registro não encontrado para restaurar.');
        return WorkRecord.fromMap(row);
      });

  Future<List<WorkHistoryEntry>> history(String userId, String recordId) =>
      guard('buscar o histórico do registro', () async {
        final rows = await _client
            .from('work_record_history')
            .select()
            .eq('user_id', userId)
            .eq('work_record_id', recordId)
            .order('changed_at', ascending: true);
        return rows.map(WorkHistoryEntry.fromMap).toList();
      });
}

class ScheduleRepository {
  const ScheduleRepository(this._client);
  final SupabaseClient _client;

  Map<String, dynamic> _payload(DateISO effectiveFrom, Map<WeekdayKey, double> hours, String? standardEntry) => {
        'effective_from': effectiveFrom,
        'weekly_hours': {for (final e in hours.entries) e.key.key: e.value},
        'monthly_hours_override': null,
        'notes': null,
        'standard_entry_time': standardEntry,
      };

  Future<List<ScheduleEntry>> listHistory(String userId) => guard('listar a carga horária', () async {
        final rows = await _client
            .from('work_schedule_history')
            .select()
            .eq('user_id', userId)
            .order('effective_from', ascending: false);
        return rows.map(ScheduleEntry.fromMap).toList();
      });

  Future<void> create(String userId, DateISO effectiveFrom, Map<WeekdayKey, double> hours, String? standardEntry) =>
      guard('salvar a carga horária', () async {
        await _client
            .from('work_schedule_history')
            .insert({'user_id': userId, ..._payload(effectiveFrom, hours, standardEntry)});
      });

  Future<void> update(
          String id, String userId, DateISO effectiveFrom, Map<WeekdayKey, double> hours, String? standardEntry) =>
      guard('atualizar a carga horária', () async {
        final row = await _client
            .from('work_schedule_history')
            .update(_payload(effectiveFrom, hours, standardEntry))
            .eq('id', id)
            .eq('user_id', userId)
            .select()
            .maybeSingle();
        if (row == null) throw const AppException('Vigência de carga horária não encontrada.');
      });

  Future<void> delete(String id, String userId) => guard('excluir a carga horária', () async {
        await _client.from('work_schedule_history').delete().eq('id', id).eq('user_id', userId);
      });
}

class SalaryRepository {
  const SalaryRepository(this._client);
  final SupabaseClient _client;

  Future<List<SalaryEntry>> listHistory(String userId) => guard('listar o histórico salarial', () async {
        final rows = await _client
            .from('salary_history')
            .select()
            .eq('user_id', userId)
            .order('effective_from', ascending: false);
        return rows.map(SalaryEntry.fromMap).toList();
      });

  Future<void> create(String userId, DateISO effectiveFrom, Decimal salary, Decimal monthlyHours) =>
      guard('salvar o salário', () async {
        await _client.from('salary_history').insert({
          'user_id': userId,
          'effective_from': effectiveFrom,
          'salary': salary.toDouble(),
          'monthly_hours': monthlyHours.toDouble(),
        });
      });

  Future<void> update(String id, String userId, DateISO effectiveFrom, Decimal salary, Decimal monthlyHours) =>
      guard('atualizar o salário', () async {
        final row = await _client
            .from('salary_history')
            .update({
              'effective_from': effectiveFrom,
              'salary': salary.toDouble(),
              'monthly_hours': monthlyHours.toDouble(),
            })
            .eq('id', id)
            .eq('user_id', userId)
            .select()
            .maybeSingle();
        if (row == null) throw const AppException('Vigência salarial não encontrada.');
      });

  Future<void> delete(String id, String userId) => guard('excluir o salário', () async {
        await _client.from('salary_history').delete().eq('id', id).eq('user_id', userId);
      });

  Future<List<OvertimeRule>> listOvertimeRules(String userId) => guard('listar as regras de hora extra', () async {
        final rows = await _client
            .from('overtime_rules')
            .select()
            .eq('user_id', userId)
            .order('effective_from', ascending: false);
        return rows.map(OvertimeRule.fromMap).toList();
      });

  Future<void> createOvertimeRule(String userId, String name, Decimal percentage, DateISO effectiveFrom) =>
      guard('salvar a regra de hora extra', () async {
        await _client.from('overtime_rules').insert({
          'user_id': userId,
          'name': name,
          'percentage': percentage.toDouble(),
          'effective_from': effectiveFrom,
        });
      });

  Future<void> updateOvertimeRule(String id, String userId, String name, Decimal percentage, DateISO effectiveFrom) =>
      guard('atualizar a regra de hora extra', () async {
        final row = await _client
            .from('overtime_rules')
            .update({'name': name, 'percentage': percentage.toDouble(), 'effective_from': effectiveFrom})
            .eq('id', id)
            .eq('user_id', userId)
            .select()
            .maybeSingle();
        if (row == null) throw const AppException('Regra de hora extra não encontrada.');
      });

  Future<void> deleteOvertimeRule(String id, String userId) => guard('excluir a regra de hora extra', () async {
        await _client.from('overtime_rules').delete().eq('id', id).eq('user_id', userId);
      });
}

class UserRepository {
  const UserRepository(this._client);
  final SupabaseClient _client;

  Future<Profile?> getProfile(String userId) => guard('buscar o perfil', () async {
        final row = await _client.from('profiles').select().eq('user_id', userId).limit(1).maybeSingle();
        return row == null ? null : Profile.fromMap(row);
      });

  Future<UserSettings?> getSettings(String userId) => guard('buscar as configurações', () async {
        final row = await _client.from('user_settings').select().eq('user_id', userId).limit(1).maybeSingle();
        return row == null ? null : UserSettings.fromMap(row);
      });

  Future<void> updateNotifications(String userId, Map<String, bool> notifications) =>
      guard('salvar as preferências', () async {
        final row = await _client
            .from('user_settings')
            .update({'notifications_enabled': notifications})
            .eq('user_id', userId)
            .select()
            .maybeSingle();
        if (row == null) throw const AppException('Configurações não encontradas.');
      });

  Future<Subscription?> getSubscription(String userId) => guard('buscar a assinatura', () async {
        final row = await _client.from('subscriptions').select().eq('user_id', userId).maybeSingle();
        return row == null ? null : Subscription.fromMap(row);
      });
}
