import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/formatting.dart';
import '../../domain/calculation.dart';
import '../../domain/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(header: true, child: Text('Configurações', style: context.text.headlineSmall)),
            ),
          ),
          const TabBar(tabs: [Tab(text: 'Preferências'), Tab(text: 'Jornada'), Tab(text: 'Financeiro')]),
          const Expanded(
            child: TabBarView(children: [_PreferencesTab(), _ScheduleTab(), _FinanceTab()]),
          ),
        ],
      ),
    );
  }
}

/// Aba com rolagem própria, largura limitada e recarregável por puxar.
class _TabScroll extends StatelessWidget {
  const _TabScroll({required this.children, this.onRefresh});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [ContentWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))],
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

// ---------------------------------------------------------------- Preferências

class _PreferencesTab extends StatefulWidget {
  const _PreferencesTab();

  @override
  State<_PreferencesTab> createState() => _PreferencesTabState();
}

class _PreferencesTabState extends State<_PreferencesTab> {
  bool _saving = false;

  Future<void> _toggle(String key, bool value) async {
    final session = AppServices.of(context).session;
    final current = {...?session.settings?.notificationsEnabled, key: value};
    setState(() => _saving = true);
    try {
      await session.updateNotifications(current);
    } catch (e) {
      if (mounted) showMessage(context, messageOf(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.theme, services.session]),
      builder: (context, _) {
        final settings = services.session.settings;
        return _TabScroll(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tema', style: context.text.titleMedium),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto)),
                        ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode)),
                        ButtonSegment(value: ThemeMode.dark, label: Text('Escuro'), icon: Icon(Icons.dark_mode)),
                      ],
                      selected: {services.theme.mode},
                      onSelectionChanged: (s) => services.theme.setMode(s.first),
                    ),
                    const SizedBox(height: 6),
                    Text('Vale só para este aparelho.', style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text('Notificações', style: context.text.titleMedium),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text('Mesmas preferências do site. O app ainda não envia notificações no aparelho.', style: context.text.bodySmall),
                    ),
                    if (settings == null)
                      const Padding(padding: EdgeInsets.all(16), child: Text('Preferências indisponíveis no momento.'))
                    else
                      for (final entry in notificationLabels.entries)
                        SwitchListTile(
                          title: Text(entry.value),
                          value: settings.isNotificationOn(entry.key),
                          onChanged: _saving ? null : (v) => _toggle(entry.key, v),
                        ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Widgets comuns

Future<DateISO?> _pickDate(BuildContext context, DateISO initial) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: toLocalDate(initial),
    firstDate: DateTime(2000),
    lastDate: DateTime(DateTime.now().year + 5),
    locale: const Locale('pt', 'BR'),
  );
  return picked == null ? null : toIso(picked);
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onChanged, required this.enabled});
  final String label;
  final DateISO value;
  final ValueChanged<DateISO> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled
          ? () async {
              final picked = await _pickDate(context, value);
              if (picked != null) onChanged(picked);
            }
          : null,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
      icon: const Icon(Icons.calendar_today, size: 18),
      label: Text('$label: ${formatDateBR(value)}'),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.title, required this.subtitle, required this.onEdit, required this.onDelete});
  final String title;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
        IconButton(tooltip: 'Excluir', icon: Icon(Icons.delete_outline, color: context.colors.error), onPressed: onDelete),
      ]),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, String what) => confirm(
      context,
      title: 'Excluir $what?',
      message: 'Esta ação não pode ser desfeita. Os dias já calculados com base nesta vigência serão recalculados com a vigência anterior.',
      confirmLabel: 'Excluir',
      destructive: true,
    );

Widget _editingBanner(BuildContext context, String text, VoidCallback onCancel) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InlineBanner(
        icon: Icons.edit,
        color: context.colors.primary,
        message: text,
        action: TextButton(onPressed: onCancel, child: const Text('Cancelar')),
      ),
    );

// ---------------------------------------------------------------- Jornada

class _ScheduleTab extends StatefulWidget {
  const _ScheduleTab();

  @override
  State<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<_ScheduleTab> {
  late final SessionController _session;
  bool _ready = false;
  List<ScheduleEntry>? _entries;
  String? _loadError;
  String? _editingId;
  bool _saving = false;
  final _formKey = GlobalKey();
  final _hours = {for (final d in WeekdayKey.values) d: TextEditingController(text: _fmt(defaultWeeklyHours[d]!))};
  String? _standardEntry;
  DateISO _effectiveFrom = todayIso();
  String? _formError;

  static String _fmt(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toString().replaceAll('.', ',');

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
    for (final c in _hours.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _session.schedule.listHistory(_session.userId);
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = messageOf(e));
    }
  }

  void _reset() {
    setState(() {
      _editingId = null;
      _standardEntry = null;
      _effectiveFrom = todayIso();
      _formError = null;
      for (final d in WeekdayKey.values) {
        _hours[d]!.text = _fmt(defaultWeeklyHours[d]!);
      }
    });
  }

  void _edit(ScheduleEntry e) {
    setState(() {
      _editingId = e.id;
      _standardEntry = e.standardEntryTime;
      _effectiveFrom = e.effectiveFrom;
      _formError = null;
      for (final d in WeekdayKey.values) {
        _hours[d]!.text = _fmt(e.weeklyHours[d]!);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _formKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: motion(ctx, 250));
    });
  }

  Future<void> _pickEntryTime() async {
    final initial = _standardEntry != null
        ? TimeOfDay(hour: int.parse(_standardEntry!.substring(0, 2)), minute: int.parse(_standardEntry!.substring(3, 5)))
        : const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked != null) {
      setState(() => _standardEntry = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    final parsed = <WeekdayKey, double>{};
    for (final d in WeekdayKey.values) {
      final v = double.tryParse(_hours[d]!.text.trim().replaceAll(',', '.'));
      if (v == null || v < 0 || v > 24) {
        setState(() => _formError = 'Horas de ${d.label}: informe um número entre 0 e 24.');
        return;
      }
      parsed[d] = v;
    }
    setState(() {
      _formError = null;
      _saving = true;
    });
    try {
      if (_editingId != null) {
        await _session.schedule.update(_editingId!, _session.userId, _effectiveFrom, parsed, _standardEntry);
      } else {
        await _session.schedule.create(_session.userId, _effectiveFrom, parsed, _standardEntry);
      }
      if (!mounted) return;
      showMessage(context, _editingId != null ? 'Vigência de carga horária atualizada.' : 'Nova vigência de carga horária salva.');
      _session.notifyDataChanged();
      _reset();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _formError = messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(ScheduleEntry e) async {
    if (!await _confirmDelete(context, 'esta vigência de carga horária') || !mounted) return;
    try {
      await _session.schedule.delete(e.id, _session.userId);
      if (!mounted) return;
      showMessage(context, 'Vigência excluída.');
      _session.notifyDataChanged();
      if (_editingId == e.id) _reset();
      await _load();
    } catch (err) {
      if (mounted) showMessage(context, messageOf(err), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return _TabScroll(
      onRefresh: _load,
      children: [
        if (_loadError != null)
          StateMessage(icon: Icons.cloud_off, title: 'Não foi possível carregar', message: _loadError, isError: true, actionLabel: 'Tentar novamente', onAction: _load)
        else if (entries == null)
          const LoadingView()
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Carga horária', style: context.text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'O horário de entrada padrão (opcional) define a partir de quando a hora extra passa a contar: chegar antes dele não gera hora extra.',
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (entries.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nenhuma carga horária configurada ainda. Defina abaixo.'))
                  else
                    for (final e in entries)
                      _EntryTile(
                        title: 'Vigente desde ${formatDateBR(e.effectiveFrom)}'
                            '${e.standardEntryTime != null ? ' · entrada padrão ${e.standardEntryTime}' : ''}',
                        subtitle: WeekdayKey.values.map((d) => '${d.shortLabel}: ${_fmt(e.weeklyHours[d]!)}h').join(' | '),
                        onEdit: () => _edit(e),
                        onDelete: () => _delete(e),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_editingId != null ? 'Editar vigência' : 'Nova vigência', style: context.text.titleMedium),
                  const SizedBox(height: 12),
                  if (_editingId != null) _editingBanner(context, 'Editando vigência de ${formatDateBR(_effectiveFrom)}.', _reset),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final d in WeekdayKey.values)
                        SizedBox(
                          width: 84,
                          child: TextField(
                            controller: _hours[d],
                            enabled: !_saving,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: d.shortLabel, suffixText: 'h'),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _pickEntryTime,
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
                          icon: const Icon(Icons.access_time, size: 18),
                          label: Text('Entrada padrão: ${_standardEntry ?? 'não definida'}'),
                        ),
                      ),
                      if (_standardEntry != null)
                        IconButton(tooltip: 'Limpar entrada padrão', icon: const Icon(Icons.close), onPressed: _saving ? null : () => setState(() => _standardEntry = null)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _DateField(label: 'Vigente a partir de', value: _effectiveFrom, enabled: !_saving, onChanged: (v) => setState(() => _effectiveFrom = v)),
                  if (_formError != null) ...[const SizedBox(height: 12), InlineBanner(icon: Icons.error_outline, message: _formError!)],
                  const SizedBox(height: 16),
                  BusyButton(label: _editingId != null ? 'Salvar alterações' : 'Salvar nova vigência', busy: _saving, onPressed: _save),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- Financeiro

class _FinanceTab extends StatefulWidget {
  const _FinanceTab();

  @override
  State<_FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<_FinanceTab> {
  late final SessionController _session;
  bool _ready = false;

  List<SalaryEntry>? _salaries;
  List<OvertimeRule>? _rules;
  int? _suggestedDivisor;
  String? _loadError;

  // Formulário de salário
  String? _salaryEditingId;
  final _salary = TextEditingController();
  final _divisor = TextEditingController(text: '$defaultMonthlyHours');
  DateISO _salaryFrom = todayIso();
  bool _savingSalary = false;
  String? _salaryError;
  final _salaryFormKey = GlobalKey();

  // Formulário de hora extra
  String? _ruleEditingId;
  final _ruleName = TextEditingController();
  final _rulePct = TextEditingController(text: '50');
  DateISO _ruleFrom = todayIso();
  bool _savingRule = false;
  String? _ruleError;
  final _ruleFormKey = GlobalKey();

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
    _salary.dispose();
    _divisor.dispose();
    _ruleName.dispose();
    _rulePct.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = _session.userId;
      final results = await Future.wait([
        _session.salary.listHistory(id),
        _session.salary.listOvertimeRules(id),
        _session.schedule.listHistory(id),
      ]);
      final schedule = ScheduleEntry.pickEffective(results[2] as List<ScheduleEntry>, todayIso());
      if (!mounted) return;
      setState(() {
        _salaries = results[0] as List<SalaryEntry>;
        _rules = results[1] as List<OvertimeRule>;
        _suggestedDivisor = schedule == null ? null : monthlyHoursDivisorFor(schedule.weeklyHours);
        _loadError = null;
        if (_salaryEditingId == null && _suggestedDivisor != null && _suggestedDivisor! > 0) {
          _divisor.text = '$_suggestedDivisor';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = messageOf(e));
    }
  }

  void _scrollTo(GlobalKey key) => WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = key.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: motion(ctx, 250));
      });

  // ---- salário

  void _resetSalary() => setState(() {
        _salaryEditingId = null;
        _salary.clear();
        _divisor.text = '${_suggestedDivisor ?? defaultMonthlyHours}';
        _salaryFrom = todayIso();
        _salaryError = null;
      });

  void _editSalary(SalaryEntry e) {
    setState(() {
      _salaryEditingId = e.id;
      _salary.text = e.salary.toString().replaceAll('.', ',');
      _divisor.text = e.monthlyHours.toString();
      _salaryFrom = e.effectiveFrom;
      _salaryError = null;
    });
    _scrollTo(_salaryFormKey);
  }

  Future<void> _saveSalary() async {
    final Decimal salary;
    try {
      salary = parseBRL(_salary.text);
    } on FormatException {
      setState(() => _salaryError = 'Informe um valor de salário válido.');
      return;
    }
    if (_salary.text.trim().isEmpty || salary < Decimal.zero) {
      setState(() => _salaryError = salary < Decimal.zero ? 'O salário não pode ser negativo.' : 'Informe o salário mensal.');
      return;
    }
    final divisor = Decimal.tryParse(_divisor.text.trim().replaceAll(',', '.'));
    if (divisor == null || divisor <= Decimal.zero) {
      setState(() => _salaryError = 'O divisor mensal deve ser maior que zero (ex.: 220).');
      return;
    }
    setState(() {
      _salaryError = null;
      _savingSalary = true;
    });
    try {
      if (_salaryEditingId != null) {
        await _session.salary.update(_salaryEditingId!, _session.userId, _salaryFrom, salary, divisor);
      } else {
        await _session.salary.create(_session.userId, _salaryFrom, salary, divisor);
      }
      if (!mounted) return;
      showMessage(context, _salaryEditingId != null ? 'Vigência salarial atualizada.' : 'Nova vigência salarial salva.');
      _resetSalary();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _salaryError = messageOf(e));
    } finally {
      if (mounted) setState(() => _savingSalary = false);
    }
  }

  Future<void> _deleteSalary(SalaryEntry e) async {
    if (!await _confirmDelete(context, 'esta vigência salarial') || !mounted) return;
    try {
      await _session.salary.delete(e.id, _session.userId);
      if (!mounted) return;
      showMessage(context, 'Vigência excluída.');
      if (_salaryEditingId == e.id) _resetSalary();
      await _load();
    } catch (err) {
      if (mounted) showMessage(context, messageOf(err), error: true);
    }
  }

  // ---- hora extra

  void _resetRule() => setState(() {
        _ruleEditingId = null;
        _ruleName.clear();
        _rulePct.text = '50';
        _ruleFrom = todayIso();
        _ruleError = null;
      });

  void _editRule(OvertimeRule r) {
    setState(() {
      _ruleEditingId = r.id;
      _ruleName.text = r.name;
      _rulePct.text = r.percentage.toString();
      _ruleFrom = r.effectiveFrom;
      _ruleError = null;
    });
    _scrollTo(_ruleFormKey);
  }

  Future<void> _saveRule() async {
    final name = _ruleName.text.trim();
    final pct = Decimal.tryParse(_rulePct.text.trim().replaceAll(',', '.'));
    if (name.isEmpty) {
      setState(() => _ruleError = 'Informe um nome para a regra (ex.: Hora extra 50%).');
      return;
    }
    if (pct == null || pct < Decimal.zero) {
      setState(() => _ruleError = 'Informe um percentual válido (0 ou mais).');
      return;
    }
    setState(() {
      _ruleError = null;
      _savingRule = true;
    });
    try {
      if (_ruleEditingId != null) {
        await _session.salary.updateOvertimeRule(_ruleEditingId!, _session.userId, name, pct, _ruleFrom);
      } else {
        await _session.salary.createOvertimeRule(_session.userId, name, pct, _ruleFrom);
      }
      if (!mounted) return;
      showMessage(context, _ruleEditingId != null ? 'Regra de hora extra atualizada.' : 'Regra de hora extra adicionada.');
      _resetRule();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _ruleError = messageOf(e));
    } finally {
      if (mounted) setState(() => _savingRule = false);
    }
  }

  Future<void> _deleteRule(OvertimeRule r) async {
    if (!await _confirmDelete(context, 'esta regra de hora extra') || !mounted) return;
    try {
      await _session.salary.deleteOvertimeRule(r.id, _session.userId);
      if (!mounted) return;
      showMessage(context, 'Regra excluída.');
      if (_ruleEditingId == r.id) _resetRule();
      await _load();
    } catch (err) {
      if (mounted) showMessage(context, messageOf(err), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final salaries = _salaries;
    final rules = _rules;
    return _TabScroll(
      onRefresh: _load,
      children: [
        if (_loadError != null)
          StateMessage(icon: Icons.cloud_off, title: 'Não foi possível carregar', message: _loadError, isError: true, actionLabel: 'Tentar novamente', onAction: _load)
        else if (salaries == null || rules == null)
          const LoadingView()
        else ...[
          _salaryCard(context, salaries),
          const SizedBox(height: 12),
          _rulesCard(context, rules),
        ],
      ],
    );
  }

  Widget _salaryCard(BuildContext context, List<SalaryEntry> salaries) {
    return Card(
      key: _salaryFormKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Salário', style: context.text.titleMedium),
            const SizedBox(height: 4),
            Text('Dados financeiros ficam só na sua conta e são usados no relatório Financeiro.', style: context.text.bodySmall),
            const SizedBox(height: 8),
            if (salaries.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nenhum salário configurado ainda. Defina abaixo.'))
            else
              for (final e in salaries)
                _EntryTile(
                  title: 'Vigente desde ${formatDateBR(e.effectiveFrom)}',
                  subtitle: '${formatBRL(e.salary)} / ${e.monthlyHours}h · hora estimada: ${formatBRL(e.hourlyRate)}',
                  onEdit: () => _editSalary(e),
                  onDelete: () => _deleteSalary(e),
                ),
            const Divider(height: 28),
            if (_salaryEditingId != null) _editingBanner(context, 'Editando vigência de ${formatDateBR(_salaryFrom)}.', _resetSalary),
            TextField(
              controller: _salary,
              enabled: !_savingSalary,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Salário mensal (R\$)', hintText: 'Ex.: 3500,00'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _divisor,
              enabled: !_savingSalary,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Divisor mensal (horas)',
                helperText: _suggestedDivisor == null ? null : 'Sugerido pela sua carga semanal: $_suggestedDivisor',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            _DateField(label: 'Vigente a partir de', value: _salaryFrom, enabled: !_savingSalary, onChanged: (v) => setState(() => _salaryFrom = v)),
            if (_salaryError != null) ...[const SizedBox(height: 12), InlineBanner(icon: Icons.error_outline, message: _salaryError!)],
            const SizedBox(height: 16),
            BusyButton(label: _salaryEditingId != null ? 'Salvar alterações' : 'Salvar nova vigência', busy: _savingSalary, onPressed: _saveSalary),
          ],
        ),
      ),
    );
  }

  Widget _rulesCard(BuildContext context, List<OvertimeRule> rules) {
    return Card(
      key: _ruleFormKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Percentuais de hora extra', style: context.text.titleMedium),
            const SizedBox(height: 4),
            Text('O piso legal (50% em dia útil, 100% em domingo e feriado) vale mesmo sem regra cadastrada.', style: context.text.bodySmall),
            const SizedBox(height: 8),
            if (rules.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nenhuma regra cadastrada.'))
            else
              for (final r in rules)
                _EntryTile(
                  title: '${r.name} · ${r.percentage}%',
                  subtitle: 'Vigente desde ${formatDateBR(r.effectiveFrom)}',
                  onEdit: () => _editRule(r),
                  onDelete: () => _deleteRule(r),
                ),
            const Divider(height: 28),
            if (_ruleEditingId != null) _editingBanner(context, 'Editando regra "${_ruleName.text}".', _resetRule),
            TextField(
              controller: _ruleName,
              enabled: !_savingRule,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Hora extra 50%'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rulePct,
              enabled: !_savingRule,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Percentual', suffixText: '%'),
            ),
            const SizedBox(height: 12),
            _DateField(label: 'Vigente a partir de', value: _ruleFrom, enabled: !_savingRule, onChanged: (v) => setState(() => _ruleFrom = v)),
            if (_ruleError != null) ...[const SizedBox(height: 12), InlineBanner(icon: Icons.error_outline, message: _ruleError!)],
            const SizedBox(height: 16),
            BusyButton(label: _ruleEditingId != null ? 'Salvar alterações' : 'Adicionar regra', busy: _savingRule, onPressed: _saveRule),
          ],
        ),
      ),
    );
  }
}
