import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/dates.dart';
import '../../data/exporter.dart';
import '../../domain/models.dart';
import '../../domain/report.dart';
import '../site_link.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'import_screen.dart';

/// Limite de segurança do período (o site não tem; evita travar o aparelho).
const _maxReportDays = 3660;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  PeriodOption _period = PeriodOption.month;
  DateISO _customStart = '';
  DateISO _customEnd = '';
  ReportType _type = ReportType.work;
  Set<String> _columns = {...allToggleableColumns};
  ExportFormat? _loading;
  ExportFormat? _succeeded;
  Timer? _successTimer;

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  bool get _customIncomplete => _period == PeriodOption.custom && (_customStart.isEmpty || _customEnd.isEmpty);
  bool get _noColumns => _type == ReportType.work && _columns.isEmpty;

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _customStart.isEmpty
          ? null
          : DateTimeRange(start: toLocalDate(_customStart), end: toLocalDate(_customEnd)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() {
      _customStart = toIso(picked.start);
      _customEnd = toIso(picked.end);
    });
  }

  /// Exportar é recurso Premium (mesma regra do site, verificada no cliente).
  Future<bool> _ensurePremium(String feature) async {
    final session = AppServices.of(context).session;
    if (!session.isPremium) await session.refreshAccount(); // pode ter assinado agora pelo site
    if (session.isPremium) return true;
    if (!mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('$feature é exclusivo dos planos pagos.'),
      action: SnackBarAction(label: 'Ver planos', onPressed: () => openSite(context, '/configuracoes?tab=assinatura')),
    ));
    return false;
  }

  Future<void> _export(ExportFormat format) async {
    if (_loading != null) return;
    if (!await _ensurePremium('Exportar ${format.label}') || !mounted) return;

    final session = AppServices.of(context).session;
    final (start, end) = rangeForOption(_period, _customStart, _customEnd);
    if (iterDates(start, end).length > _maxReportDays) {
      showMessage(context, 'Escolha um período de até 10 anos.', error: true);
      return;
    }

    setState(() => _loading = format);
    try {
      final userId = session.userId;
      final results = await Future.wait([
        session.work.listByRange(userId, start, end),
        session.schedule.listHistory(userId),
        if (_type == ReportType.finance) session.salary.listHistory(userId),
        if (_type == ReportType.finance) session.salary.listOvertimeRules(userId),
      ]);
      final records = results[0] as List<WorkRecord>;
      final byDate = {for (final r in records) r.workDate: r};
      final days = calculateDays(
        start: start,
        end: end,
        recordsByDate: byDate,
        schedules: results[1] as List<ScheduleEntry>,
      );
      final table = _type == ReportType.work
          ? buildWorkReport(days: days, recordsByDate: byDate, selectedColumns: _columns)
          : buildFinanceReport(
              start: start,
              end: end,
              days: days,
              salaryHistory: results[2] as List<SalaryEntry>,
              overtimeRules: results[3] as List<OvertimeRule>,
            );
      final bytes = await buildExport(table, format);
      await shareFile('relatorio_${start}_a_$end.${format.name}', bytes);
      if (!mounted) return;
      setState(() => _succeeded = format);
      _successTimer?.cancel();
      _successTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _succeeded = null);
      });
    } catch (e) {
      if (mounted) showMessage(context, messageOf(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (start, end) = _customIncomplete ? ('', '') : rangeForOption(_period, _customStart, _customEnd);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Semantics(header: true, child: Text('Relatórios', style: context.text.headlineSmall))),
                  IconButton.filledTonal(
                    tooltip: 'Importar registros',
                    icon: const Icon(Icons.upload_file),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
                  ),
                ],
              ),
              Text('Exporte seus dados para usar fora do app.', style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
              const SectionTitle('1. Período e conteúdo'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final o in PeriodOption.values)
                    ChoiceChip(
                      label: Text(o.label),
                      selected: _period == o,
                      onSelected: (_) => setState(() => _period = o),
                    ),
                ],
              ),
              if (_period == PeriodOption.custom) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickCustomRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(_customIncomplete ? 'Escolher intervalo' : '${formatDateBR(_customStart)} a ${formatDateBR(_customEnd)}'),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${formatDateBR(start)} a ${formatDateBR(end)}', style: context.text.bodySmall),
                ),
              const SizedBox(height: 12),
              SegmentedButton<ReportType>(
                segments: const [
                  ButtonSegment(value: ReportType.work, label: Text('Jornada'), icon: Icon(Icons.schedule)),
                  ButtonSegment(value: ReportType.finance, label: Text('Financeiro'), icon: Icon(Icons.attach_money)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: motion(context),
                child: _type == ReportType.work ? _columnPicker(context) : _financeInfo(context),
              ),
              const SectionTitle('2. Exporte'),
              if (_customIncomplete) Text('Escolha o intervalo para poder exportar.', style: context.text.bodySmall?.copyWith(color: context.status.warning)),
              if (_noColumns) Text('Selecione ao menos uma coluna para poder exportar.', style: context.text.bodySmall?.copyWith(color: context.status.warning)),
              const SizedBox(height: 4),
              for (final f in ExportFormat.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ExportTile(
                    format: f,
                    loading: _loading == f,
                    succeeded: _succeeded == f,
                    enabled: _loading == null && !_customIncomplete && !_noColumns,
                    onTap: () => _export(f),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _financeInfo(BuildContext context) => Padding(
        key: const ValueKey('finance'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Inclui: período, horas normais, horas extras, valor da hora e os valores estimados (normal, extra e total) — um resumo, não um registro dia a dia.',
          style: context.text.bodyMedium,
        ),
      );

  Widget _columnPicker(BuildContext context) => Column(
        key: const ValueKey('work'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('"Data" sempre entra. ${_columns.length} de ${allToggleableColumns.length} colunas selecionadas.', style: context.text.bodySmall),
              ),
              TextButton(onPressed: () => setState(() => _columns = {...allToggleableColumns}), child: const Text('Todas')),
              TextButton(onPressed: () => setState(() => _columns = {}), child: const Text('Limpar')),
            ],
          ),
          for (final (title, cols) in workColumnGroups) ...[
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(title, style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant))),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in cols)
                  FilterChip(
                    label: Text(c.label),
                    selected: _columns.contains(c.key),
                    onSelected: (on) => setState(() => on ? _columns.add(c.key) : _columns.remove(c.key)),
                  ),
              ],
            ),
          ],
        ],
      );
}

class _ExportTile extends StatelessWidget {
  const _ExportTile({required this.format, required this.loading, required this.succeeded, required this.enabled, required this.onTap});
  final ExportFormat format;
  final bool loading;
  final bool succeeded;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (format) {
      ExportFormat.xlsx => Icons.table_chart_outlined,
      ExportFormat.csv => Icons.description_outlined,
      ExportFormat.pdf => Icons.picture_as_pdf_outlined,
    };
    return Opacity(
      opacity: enabled || loading ? 1 : 0.5,
      child: Card(
        child: ListTile(
          enabled: enabled,
          onTap: enabled ? onTap : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: context.colors.primaryContainer,
            child: AnimatedSwitcher(
              duration: motion(context, 200),
              child: loading
                  ? const SizedBox(key: ValueKey('l'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : succeeded
                      ? Icon(Icons.check, key: const ValueKey('s'), color: context.status.success)
                      : Icon(icon, key: const ValueKey('i')),
            ),
          ),
          title: Text(loading ? 'Exportando...' : 'Exportar ${format.label}'),
          subtitle: Text(format.description),
        ),
      ),
    );
  }
}
