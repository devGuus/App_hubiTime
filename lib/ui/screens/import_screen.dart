import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/formatting.dart';
import '../../data/errors.dart';
import '../../data/exporter.dart';
import '../../domain/import_parser.dart';
import '../../domain/import_plan.dart';
import '../../domain/models.dart';
import '../site_link.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _chunkSize = 50;

class _ImportResult {
  int created = 0;
  int updated = 0;
  int skipped = 0;
  final List<String> failures = [];
  String? interruptedBy;
}

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _fileName;
  List<ReviewRow> _rows = [];
  bool _reading = false;
  bool _importing = false;
  int _progress = 0;
  String? _fileError;
  _ImportResult? _result;

  int _count(ImportStatus s) => _rows.where((r) => r.status == s).length;

  Future<void> _pickFile() async {
    if (_reading || _importing) return;
    final session = AppServices.of(context).session;
    setState(() {
      _fileError = null;
      _result = null;
    });
    try {
      final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: importExtensions);
      if (picked == null || !mounted) return;
      setState(() => _reading = true);

      final size = await picked.length();
      if (size != null && size > maxImportFileBytes) {
        throw const ImportFileException('Arquivo muito grande (limite de 5 MB). Divida em arquivos menores.');
      }
      final Uint8List bytes = await picked.readAsBytes();
      final parsed = parseImportFile(picked.name, bytes);
      if (parsed.isEmpty) throw const ImportFileException('Nenhuma linha encontrada no arquivo.');

      final span = dateSpan(parsed);
      final existing = span == null
          ? <WorkRecord>[]
          : await session.work.listByRange(session.userId, span.$1, span.$2, includeArchived: true);
      if (!mounted) return;
      setState(() {
        _fileName = picked.name;
        _rows = classifyRows(parsed, {for (final r in existing) r.workDate: r});
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _fileName = null;
        _fileError = e is ImportFileException ? e.message : messageOf(e);
      });
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _confirm() async {
    if (_importing) return;
    final session = AppServices.of(context).session;
    if (!session.isPremium) await session.refreshAccount();
    if (!mounted) return;
    if (!session.isPremium) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: const Text('Importar registros é exclusivo dos planos pagos.'),
        action: SnackBarAction(label: 'Ver planos', onPressed: () => openSite(context, '/configuracoes?tab=assinatura')),
      ));
      return;
    }

    final toCreate = _count(ImportStatus.novo);
    final toUpdate = _rows.where((r) => r.status == ImportStatus.conflito && r.overwrite).length;
    if (toCreate + toUpdate == 0) {
      showMessage(context, 'Nada para importar: nenhuma linha nova e nenhuma data existente marcada para sobrescrever.');
      return;
    }
    final ok = await confirm(
      context,
      title: 'Confirmar importação',
      message: 'Serão criados $toCreate registro(s) e sobrescritos $toUpdate. As demais linhas serão ignoradas.',
      confirmLabel: 'Importar',
    );
    if (!ok || !mounted) return;

    setState(() {
      _importing = true;
      _progress = 0;
    });
    final result = _ImportResult();
    final userId = session.userId;
    final repo = session.work;
    try {
      final fresh = _rows.where((r) => r.status == ImportStatus.novo).toList();
      for (var i = 0; i < fresh.length; i += _chunkSize) {
        final chunk = fresh.sublist(i, i + _chunkSize > fresh.length ? fresh.length : i + _chunkSize);
        try {
          await repo.createMany(userId, [for (final r in chunk) (r.parsed.workDate!, _draftOf(r))]);
          result.created += chunk.length;
        } on OfflineException {
          rethrow;
        } on AppException {
          // O lote inteiro foi recusado: reenvia linha a linha para isolar a que falhou.
          for (final r in chunk) {
            try {
              await repo.create(userId, r.parsed.workDate!, _draftOf(r));
              result.created++;
            } on OfflineException {
              rethrow;
            } on AppException catch (e) {
              result.failures.add('Linha ${r.parsed.rowNumber} (${formatDateBR(r.parsed.workDate)}): ${e.message}');
            }
          }
        }
        if (mounted) setState(() => _progress += chunk.length);
      }

      for (final r in _rows.where((r) => r.status == ImportStatus.conflito && r.overwrite && r.existing != null)) {
        try {
          await repo.update(r.existing!.id, userId, r.existing!.version, _draftOf(r));
          result.updated++;
        } on OfflineException {
          rethrow;
        } on AppException catch (e) {
          result.failures.add('Linha ${r.parsed.rowNumber} (${formatDateBR(r.parsed.workDate)}): ${e.message}');
        }
        if (mounted) setState(() => _progress++);
      }
    } on OfflineException catch (e) {
      result.interruptedBy = '${e.message} A importação foi interrompida; o que já foi enviado está salvo.';
    }

    result.skipped = _rows.length - result.created - result.updated - result.failures.length;
    if (!mounted) return;
    setState(() {
      _importing = false;
      _result = result;
      // Limpa a revisão: reimportar o mesmo arquivo exige escolhê-lo de novo
      // (e aí as datas já importadas aparecem como "já existe").
      _rows = [];
      _fileName = null;
    });
  }

  WorkRecordDraft _draftOf(ReviewRow r) => WorkRecordDraft(
        entryTime: r.parsed.entryTime,
        lunchStart: r.parsed.lunchStart,
        lunchEnd: r.parsed.lunchEnd,
        exitTime: r.parsed.exitTime,
        dayType: r.parsed.dayType,
        notes: r.parsed.notes,
      );

  Future<void> _shareTemplate(bool xlsx) async {
    try {
      if (xlsx) {
        await shareFile('modelo_importacao_hubi_time.xlsx', Uint8List.fromList(importTemplateXlsx()));
      } else {
        await shareFile('modelo_importacao_hubi_time.csv', Uint8List.fromList(utf8.encode(importTemplateCsv())));
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Não consegui compartilhar o modelo.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = _count(ImportStatus.conflito);
    return Scaffold(
      appBar: AppBar(title: const Text('Importar registros')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(child: ContentWidth(child: _instructions(context))),
            ),
            if (_rows.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: ContentWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('3. Revise e confirme', style: context.text.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          '${_count(ImportStatus.novo)} novo(s), $conflicts data(s) já existente(s), ${_count(ImportStatus.erro)} com erro (serão ignoradas).',
                          style: context.text.bodyMedium,
                        ),
                        if (conflicts > 0)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Sobrescrever todas as datas já existentes'),
                            value: _rows.where((r) => r.status == ImportStatus.conflito).every((r) => r.overwrite),
                            onChanged: _importing
                                ? null
                                : (v) => setState(() {
                                      for (final r in _rows.where((r) => r.status == ImportStatus.conflito)) {
                                        r.overwrite = v;
                                      }
                                    }),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, i) => ContentWidth(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RowCard(
                        row: _rows[i],
                        enabled: !_importing,
                        onOverwrite: (v) => setState(() => _rows[i].overwrite = v),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: ContentWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_importing) ...[
                          LinearProgressIndicator(value: _rows.isEmpty ? null : _progress / _rows.length),
                          const SizedBox(height: 8),
                          Text('Importando... $_progress de ${_rows.length}', textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                        ],
                        BusyButton(label: 'Confirmar importação', busy: _importing, onPressed: _confirm),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (_result != null)
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(child: ContentWidth(child: _resultCard(context, _result!))),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _instructions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1. Prepare o arquivo', style: context.text.titleMedium),
                const SizedBox(height: 8),
                const Text('Monte uma planilha com uma linha de cabeçalho e uma linha por dia, com estas colunas:'),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final h in importHeaders) Chip(label: Text(h))]),
                const SizedBox(height: 12),
                const Text('• Data em DD/MM/AAAA e horários em HH:MM. Em folgas e férias, deixe os horários em branco.'),
                const SizedBox(height: 4),
                Text('• Tipo de dia (opcional): ${DayType.values.map((t) => t.label).join(', ')}. Em branco = "Dia normal".'),
                const SizedBox(height: 4),
                const Text('• Salve a planilha como .xlsx ou .csv (no Excel: Arquivo → Salvar como; no Google Planilhas: Arquivo → Fazer download).'),
                const SizedBox(height: 4),
                const Text('• Anotações em outro formato? Peça para uma IA (Claude, ChatGPT…) reescrever nas colunas acima antes de enviar.'),
                const SizedBox(height: 12),
                Text('Baixe um modelo pronto para preencher:', style: context.text.labelLarge),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => _shareTemplate(false), icon: const Icon(Icons.download), label: const Text('Modelo .csv')),
                  OutlinedButton.icon(onPressed: () => _shareTemplate(true), icon: const Icon(Icons.download), label: const Text('Modelo .xlsx')),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('2. Escolha o arquivo', style: context.text.titleMedium),
                const SizedBox(height: 4),
                Text('Aceita .csv, .txt ou .xlsx, até 5 MB. Você revisa tudo antes de salvar.', style: context.text.bodySmall),
                const SizedBox(height: 12),
                BusyButton(label: _fileName == null ? 'Selecionar arquivo' : 'Trocar arquivo', icon: Icons.folder_open, busy: _reading, tonal: true, onPressed: _pickFile),
                if (_fileName != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Arquivo: $_fileName', style: context.text.bodySmall)),
                AnimatedSize(
                  duration: motion(context),
                  child: _fileError == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(padding: const EdgeInsets.only(top: 12), child: InlineBanner(icon: Icons.error_outline, message: _fileError!)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultCard(BuildContext context, _ImportResult r) {
    final hasProblems = r.failures.isNotEmpty || r.interruptedBy != null;
    final tone = hasProblems ? context.status.warning : context.status.success;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(hasProblems ? Icons.warning_amber_rounded : Icons.check_circle, color: tone),
              const SizedBox(width: 8),
              Text(hasProblems ? 'Importação com pendências' : 'Importação concluída', style: context.text.titleMedium),
            ]),
            const SizedBox(height: 8),
            Text('${r.created} registro(s) criado(s), ${r.updated} atualizado(s), ${r.skipped} ignorado(s), ${r.failures.length} com falha.'),
            if (r.interruptedBy != null) ...[const SizedBox(height: 8), Text(r.interruptedBy!)],
            for (final f in r.failures.take(20)) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $f', style: context.text.bodySmall)),
            if (r.failures.length > 20) Text('… e mais ${r.failures.length - 20} falha(s).', style: context.text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.row, required this.enabled, required this.onOverwrite});
  final ReviewRow row;
  final bool enabled;
  final ValueChanged<bool> onOverwrite;

  @override
  Widget build(BuildContext context) {
    final p = row.parsed;
    final (label, color, icon) = switch (row.status) {
      ImportStatus.novo => ('Novo', context.status.success, Icons.check),
      ImportStatus.conflito => ('Já existe', context.status.warning, Icons.warning_amber_rounded),
      ImportStatus.erro => ('Erro', context.colors.error, Icons.cancel_outlined),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.workDate != null ? formatDateBR(p.workDate) : 'Linha ${p.rowNumber}', style: context.text.titleSmall),
                ),
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${p.dayType.label} · ${formatTimeOrPlaceholder(p.entryTime)} | ${formatTimeOrPlaceholder(p.lunchStart)}–${formatTimeOrPlaceholder(p.lunchEnd)} | ${formatTimeOrPlaceholder(p.exitTime)}',
              style: context.text.bodySmall,
            ),
            for (final e in p.errors) Text('• $e', style: context.text.bodySmall?.copyWith(color: context.colors.error)),
            if (row.status != ImportStatus.erro)
              for (final w in p.warnings) Text('• $w', style: context.text.bodySmall?.copyWith(color: context.status.warning)),
            if (row.status == ImportStatus.conflito)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Sobrescrever esta data'),
                value: row.overwrite,
                onChanged: enabled ? onOverwrite : null,
              ),
          ],
        ),
      ),
    );
  }
}
