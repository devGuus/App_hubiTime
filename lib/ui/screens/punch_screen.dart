import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/formatting.dart';
import '../../data/errors.dart';
import '../../domain/calculation.dart';
import '../../domain/models.dart';
import '../../domain/punch.dart';
import '../../domain/validators.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'day_editor.dart';

/// Registro que não chegou ao servidor. Guarda o horário capturado no toque
/// para que "Tentar novamente" não use o horário errado.
class _PendingPunch {
  const _PendingPunch(this.step, this.date, this.time, this.message);
  final PunchStep step;
  final DateISO date;
  final String time;
  final String message;
}

class PunchScreen extends StatefulWidget {
  const PunchScreen({super.key});

  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen> with WidgetsBindingObserver {
  late SessionController _session;
  Timer? _clock;
  Timer? _flashTimer;

  DateISO _date = todayIso();
  DateTime _now = DateTime.now();
  WorkRecord? _record;
  ScheduleEntry? _schedule;
  bool _loading = true;
  String? _loadError;
  bool _busy = false;
  _PendingPunch? _pending;
  PunchStep? _flashStep;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _session = AppServices.of(context).session;
    _revision = _session.dataRevision;
    _session.addListener(_onSessionChanged);
    _load();
  }

  bool _initialized = false;
  int _revision = 0;

  /// Carga horária alterada em Configurações: recarrega o previsto/saldo.
  void _onSessionChanged() {
    if (_session.dataRevision != _revision) {
      _revision = _session.dataRevision;
      _load(silent: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ao voltar para o app (ex.: virou o dia ou o registro mudou no site), recarrega.
    if (state == AppLifecycleState.resumed && !_busy) _load(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_initialized) _session.removeListener(_onSessionChanged);
    _clock?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final date = todayIso();
    try {
      final results = await Future.wait([
        _session.work.getByDate(_session.userId, date),
        _session.schedule.listHistory(_session.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _date = date;
        _record = results[0] as WorkRecord?;
        _schedule = ScheduleEntry.pickEffective(results[1] as List<ScheduleEntry>, date);
        _loadError = null;
        _now = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      // Em recarga silenciosa, mantém o que já está na tela.
      if (!silent || _record == null) setState(() => _loadError = messageOf(e));
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  PunchStep? get _nextStep =>
      nextPunchStep(
        _record?.times ?? const [null, null, null, null],
        dayType: _record?.dayType ?? DayType.normal,
        archived: _record?.isArchived ?? false,
      );

  Future<void> _punch(PunchStep step, {_PendingPunch? retry}) async {
    if (_busy) return;
    final captured = DateTime.now();
    final date = retry?.date ?? todayIso(captured);
    final time = retry?.time ?? formatClock(captured);

    if (date != _date) {
      // Virou o dia com a tela aberta: não grava no dia errado.
      await _load();
      if (mounted) showMessage(context, 'O dia mudou. Confira os registros de hoje e toque novamente.');
      return;
    }

    final times = [...(_record?.times ?? const [null, null, null, null])];
    times[step.index] = time;
    final warnings = detectTimeInconsistencies(times[0], times[1], times[2], times[3]);
    if (warnings.isNotEmpty) {
      final ok = await confirm(
        context,
        title: 'Horário inconsistente',
        message: '${warnings.map((w) => w.message).join('\n')}\n\nRegistrar $time mesmo assim?',
        confirmLabel: 'Registrar',
      );
      if (!ok || !mounted) return;
    }

    setState(() {
      _busy = true;
      _pending = null;
    });
    try {
      final saved = await _saveTime(step, time, date);
      if (!mounted) return;
      if (saved == null) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _record = saved;
        _flashStep = step;
      });
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _flashStep = null);
      });
      showMessage(context, '${step.label} registrada às $time e salva no servidor.');
    } on OfflineException catch (e) {
      if (mounted) setState(() => _pending = _PendingPunch(step, date, time, e.message));
    } on AppException catch (e) {
      if (mounted) setState(() => _pending = _PendingPunch(step, date, time, e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Grava a batida respeitando o que já existe no servidor. Retorna null se
  /// não gravou nada (e já avisou o usuário).
  Future<WorkRecord?> _saveTime(PunchStep step, String time, DateISO date) async {
    final repo = _session.work;
    final userId = _session.userId;
    try {
      if (_record == null) {
        return await repo.createWithTime(userId, date, step.column, time);
      }
      return await repo.updateTime(_record!.id, userId, _record!.version, step.column, time);
    } on DuplicateRecordException {
      // Outro aparelho/o site criou o dia entre a leitura e o toque.
      await _load(silent: true);
      _explainRace();
      return null;
    } on ConflictException {
      await _load(silent: true);
      _explainRace();
      return null;
    }
  }

  void _explainRace() {
    if (!mounted) return;
    showMessage(
      context,
      'Este dia foi alterado em outro lugar. Atualizamos a tela — confira os horários e toque novamente se ainda for necessário.',
      error: true,
    );
  }

  Future<void> _openEditor() async {
    await showDayEditor(context, date: _date);
    if (mounted) await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(silent: true),
            child: _body(context),
          ),
        ),
        if (!_loading && _loadError == null) _ActionBar(
          step: _nextStep,
          record: _record,
          busy: _busy,
          flash: _flashStep != null,
          onPunch: (s) => _punch(s),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return ListView(children: const [SizedBox(height: 120), LoadingView()]);
    if (_loadError != null && _record == null) {
      return ListView(children: [
        const SizedBox(height: 80),
        StateMessage(icon: Icons.cloud_off, title: 'Não foi possível carregar o dia', message: _loadError, isError: true, actionLabel: 'Tentar novamente', onAction: _load),
      ]);
    }

    final record = _record;
    final calc = computeDay(
      record?.fields ?? WorkRecordFields(workDate: _date),
      _schedule?.fields,
      _now,
    );
    final times = record?.times ?? const [null, null, null, null];
    final next = _nextStep;
    final warnings = detectTimeInconsistencies(times[0], times[1], times[2], times[3]);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(date: _date, now: _now, onEdit: _openEditor),
              const SizedBox(height: 16),
              if (_pending != null) ...[
                InlineBanner(
                  icon: Icons.cloud_off,
                  message: 'NÃO SALVO: ${_pending!.step.label} às ${_pending!.time}. ${_pending!.message}',
                  action: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: _busy ? null : () => _punch(_pending!.step, retry: _pending), child: const Text('Reenviar')),
                    TextButton(onPressed: () => setState(() => _pending = null), child: const Text('Descartar')),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              if (record != null && record.isArchived) ...[
                const InlineBanner(icon: Icons.inventory_2_outlined, message: 'O registro de hoje está arquivado. Restaure-o em "Corrigir horários" para editar.'),
                const SizedBox(height: 12),
              ] else if (record != null && !record.dayType.countsAsExpectedWorkday) ...[
                InlineBanner(icon: Icons.event_busy, color: context.colors.primary, message: 'Hoje está marcado como "${record.dayType.label}". Não há horários para registrar.'),
                const SizedBox(height: 12),
              ],
              if (warnings.isNotEmpty) ...[
                InlineBanner(icon: Icons.warning_amber_rounded, color: context.status.warning, message: warnings.map((w) => w.message).join('\n')),
                const SizedBox(height: 12),
              ],
              for (final step in PunchStep.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _StepTile(
                    step: step,
                    time: times[step.index],
                    isNext: step == next,
                    flash: _flashStep == step,
                    onTap: _openEditor,
                  ),
                ),
              const SizedBox(height: 6),
              _Summary(calc: calc, hasSchedule: _schedule != null, hasRecord: record != null),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.date, required this.now, required this.onEdit});
  final DateISO date;
  final DateTime now;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text('Ponto de hoje', style: context.text.headlineSmall)),
              Text(formatLongDate(date), style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
            ],
          ),
        ),
        Text(formatClock(now), style: context.text.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 4),
        IconButton(tooltip: 'Corrigir horários', onPressed: onEdit, icon: const Icon(Icons.edit_calendar_outlined)),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step, required this.time, required this.isNext, required this.flash, required this.onTap});
  final PunchStep step;
  final String? time;
  final bool isNext;
  final bool flash;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = time != null;
    final colors = context.colors;
    final background = flash
        ? context.status.success.withValues(alpha: 0.18)
        : isNext
            ? colors.primaryContainer
            : colors.surfaceContainerLow;
    final label = done
        ? '${step.label}: $time'
        : isNext
            ? '${step.label}: próxima ação'
            : '${step.label}: não registrada';
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      onTapHint: 'Corrigir horários',
      child: AnimatedContainer(
        duration: motion(context, 250),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isNext ? colors.primary : colors.outlineVariant, width: isNext ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: motion(context, 250),
                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    done ? Icons.check_circle : (isNext ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    key: ValueKey('$done$isNext'),
                    color: done ? context.status.success : (isNext ? colors.primary : colors.outline),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(step.label, style: context.text.titleMedium)),
                Text(
                  time ?? '--:--',
                  style: context.text.titleLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: done ? colors.onSurface : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.calc, required this.hasSchedule, required this.hasRecord});
  final DayCalculation calc;
  final bool hasSchedule;
  final bool hasRecord;

  @override
  Widget build(BuildContext context) {
    final status = !hasRecord
        ? 'Sem registro hoje'
        : calc.isComplete
            ? 'Dia completo'
            : calc.isInProgress
                ? 'Em andamento'
                : 'Incompleto';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status, style: context.text.titleSmall?.copyWith(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _Stat(label: 'Trabalhado', value: formatMinutesAsHours(calc.workedMinutes))),
                Expanded(child: _Stat(label: 'Previsto', value: hasSchedule ? formatMinutesAsHours(calc.expectedMinutes) : '—')),
                Expanded(
                  child: _Stat(
                    label: 'Saldo',
                    value: hasSchedule ? formatMinutesAsHours(calc.balanceMinutes, showSign: true) : '—',
                    color: !hasSchedule ? null : (calc.balanceMinutes >= 0 ? context.status.success : context.colors.error),
                  ),
                ),
              ],
            ),
            if (!hasSchedule) ...[
              const SizedBox(height: 10),
              Text('Defina sua carga horária em Configurações para ver o previsto e o saldo.', style: context.text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: context.text.titleMedium?.copyWith(color: color)),
        ],
      );
}

/// Botão principal fixo na base da tela (alcance com o polegar).
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.step, required this.record, required this.busy, required this.flash, required this.onPunch});
  final PunchStep? step;
  final WorkRecord? record;
  final bool busy;
  final bool flash;
  final ValueChanged<PunchStep> onPunch;

  @override
  Widget build(BuildContext context) {
    final String label;
    final IconData icon;
    if (flash) {
      label = 'Registrado';
      icon = Icons.check;
    } else if (step != null) {
      label = step!.actionLabel;
      icon = Icons.touch_app;
    } else if (record != null && record!.isArchived) {
      label = 'Registro arquivado';
      icon = Icons.inventory_2_outlined;
    } else if (record != null && !record!.dayType.countsAsExpectedWorkday) {
      label = record!.dayType.label;
      icon = Icons.event_busy;
    } else {
      label = 'Jornada de hoje concluída';
      icon = Icons.task_alt;
    }
    final enabled = step != null && !flash;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: ContentWidth(
        child: SizedBox(
          width: double.infinity,
          height: 60,
          child: Semantics(
            button: true,
            enabled: enabled,
            child: BusyButton(
              label: label,
              icon: icon,
              busy: busy,
              onPressed: enabled ? () => onPunch(step!) : null,
            ),
          ),
        ),
      ),
    );
  }
}
