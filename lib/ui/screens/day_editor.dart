/// Correção de um dia: os 4 horários, tipo de dia, observações, arquivar /
/// restaurar e histórico de alterações. Mesmas regras do DayEditor do site
/// (concorrência otimista por `version`, aviso sem bloqueio de inconsistências).
library;

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/formatting.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';
import '../../domain/punch.dart';
import '../../domain/validators.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> showDayEditor(BuildContext context, {required DateISO date}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => DayEditor(date: date),
  );
}

const _fieldLabels = {
  'entry_time': 'Entrada',
  'lunch_start': 'Saída para almoço',
  'lunch_end': 'Retorno do almoço',
  'exit_time': 'Saída',
  'day_type': 'Tipo de dia',
  'notes': 'Observações',
  'status': 'Status',
};

String describeHistory(WorkHistoryEntry e) {
  final label = _fieldLabels[e.fieldChanged] ?? e.fieldChanged ?? '';
  String show(String? v) => v == null || v.isEmpty ? '--:--' : (v.length >= 5 && v.contains(':') ? v.substring(0, 5) : v);
  switch (e.action) {
    case 'CREATE':
      return '$label registrado: ${e.newValue}';
    case 'ARCHIVE':
      return 'Registro arquivado';
    case 'RESTORE':
      return 'Registro restaurado';
    default:
      return '$label alterado: ${show(e.oldValue)} → ${show(e.newValue)}';
  }
}

class DayEditor extends StatefulWidget {
  const DayEditor({super.key, required this.date});
  final DateISO date;

  @override
  State<DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<DayEditor> {
  late final SessionController _session;
  bool _ready = false;

  WorkRecord? _record;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  List<WorkHistoryEntry>? _history;

  final _times = <String?>[null, null, null, null];
  DayType _dayType = DayType.normal;
  final _notes = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    _session = AppServices.of(context).session;
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _apply(WorkRecord? r) {
    _record = r;
    for (var i = 0; i < 4; i++) {
      _times[i] = r?.times[i];
    }
    _dayType = r?.dayType ?? DayType.normal;
    _notes.text = r?.notes ?? '';
    _history = null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final r = await _session.work.getByDate(_session.userId, widget.date);
      if (mounted) setState(() => _apply(r));
    } catch (e) {
      if (mounted) setState(() => _loadError = messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _editable => !(_record?.isArchived ?? false);

  Future<void> _pickTime(int index) async {
    final current = _times[index];
    final initial = current != null
        ? TimeOfDay(hour: int.parse(current.substring(0, 2)), minute: int.parse(current.substring(3, 5)))
        : TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: PunchStep.values[index].label,
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null || !mounted) return;
    setState(() => _times[index] =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _run(Future<WorkRecord> Function() action, String success) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await action();
      if (!mounted) return;
      setState(() => _apply(saved));
      showMessage(context, success);
    } on ConflictException catch (e) {
      await _load();
      if (mounted) showMessage(context, e.message, error: true);
    } on DuplicateRecordException {
      await _load();
      if (mounted) showMessage(context, 'Este dia já tinha sido criado em outro lugar. Recarregamos — confira e salve novamente.', error: true);
    } catch (e) {
      if (mounted) showMessage(context, messageOf(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  WorkRecordDraft get _draft => WorkRecordDraft(
        entryTime: _times[0],
        lunchStart: _times[1],
        lunchEnd: _times[2],
        exitTime: _times[3],
        dayType: _dayType,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );

  Future<void> _save() => _run(() {
        final r = _record;
        return r == null
            ? _session.work.create(_session.userId, widget.date, _draft)
            : _session.work.update(r.id, _session.userId, r.version, _draft);
      }, 'Registro salvo no servidor.');

  Future<void> _archive() async {
    final ok = await confirm(
      context,
      title: 'Arquivar registro',
      message: 'O registro deixa de aparecer nos relatórios, mas pode ser restaurado depois.',
      confirmLabel: 'Arquivar',
      destructive: true,
    );
    if (ok) await _run(() => _session.work.archive(_record!.id, _session.userId), 'Registro arquivado.');
  }

  Future<void> _loadHistory() async {
    if (_record == null || _history != null) return;
    try {
      final h = await _session.work.history(_session.userId, _record!.id);
      if (mounted) setState(() => _history = h);
    } catch (e) {
      if (mounted) showMessage(context, messageOf(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: _loading
          ? const SizedBox(height: 240, child: LoadingView())
          : _loadError != null
              ? SizedBox(
                  height: 260,
                  child: StateMessage(icon: Icons.cloud_off, title: 'Não foi possível carregar', message: _loadError, isError: true, actionLabel: 'Tentar novamente', onAction: _load),
                )
              : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final warnings = detectTimeInconsistencies(_times[0], _times[1], _times[2], _times[3]);
    final incomplete = _dayType == DayType.normal && _times.any((t) => t == null);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Corrigir horários', style: context.text.titleLarge),
          Text(formatLongDate(widget.date), style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 14),
          if (!_editable) ...[
            const InlineBanner(icon: Icons.inventory_2_outlined, message: 'Este registro está arquivado e não pode ser editado. Restaure para voltar a editar.'),
            const SizedBox(height: 12),
          ],
          if (warnings.isNotEmpty) ...[
            InlineBanner(icon: Icons.warning_amber_rounded, color: context.status.warning, message: warnings.map((w) => w.message).join('\n')),
            const SizedBox(height: 12),
          ],
          for (final step in PunchStep.values)
            _TimeRow(
              label: step.label,
              value: _times[step.index],
              enabled: _editable && !_saving,
              onPick: () => _pickTime(step.index),
              onClear: () => setState(() => _times[step.index] = null),
            ),
          if (incomplete && _editable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Registro deste dia ainda está incompleto.', style: context.text.bodySmall?.copyWith(color: context.status.warning)),
            ),
          const SizedBox(height: 14),
          DropdownButtonFormField<DayType>(
            initialValue: _dayType,
            decoration: const InputDecoration(labelText: 'Tipo de dia'),
            items: [for (final t in DayType.values) DropdownMenuItem(value: t, child: Text(t.label))],
            onChanged: _editable && !_saving ? (v) => setState(() => _dayType = v ?? DayType.normal) : null,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notes,
            enabled: _editable && !_saving,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Observações (opcional)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 18),
          if (_editable) BusyButton(label: 'Salvar', busy: _saving, onPressed: _save),
          if (_record != null) ...[
            const SizedBox(height: 10),
            _record!.isArchived
                ? OutlinedButton(
                    onPressed: _saving ? null : () => _run(() => _session.work.restore(_record!.id, _session.userId), 'Registro restaurado.'),
                    child: const Text('Restaurar registro'),
                  )
                : OutlinedButton(
                    onPressed: _saving ? null : _archive,
                    style: OutlinedButton.styleFrom(foregroundColor: context.colors.error),
                    child: const Text('Arquivar registro'),
                  ),
            ExpansionTile(
              title: const Text('Histórico de alterações'),
              tilePadding: EdgeInsets.zero,
              onExpansionChanged: (open) => open ? _loadHistory() : null,
              children: [
                if (_history == null)
                  const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
                else if (_history!.isEmpty)
                  const Padding(padding: EdgeInsets.all(12), child: Text('Nenhuma alteração registrada ainda.'))
                else
                  for (final e in _history!)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(describeHistory(e)),
                      subtitle: Text('${formatDateBR(toIso(e.changedAt))} ${formatClock(e.changedAt)}'),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.value, required this.enabled, required this.onPick, required this.onClear});
  final String label;
  final String? value;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: enabled ? onPick : null,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  Text(value ?? '--:--', style: context.text.titleMedium),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Limpar $label',
            onPressed: enabled && value != null ? onClear : null,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
