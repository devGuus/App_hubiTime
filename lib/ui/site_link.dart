import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import 'widgets/common.dart';

/// Abre uma página do site (SITE_URL do ambiente) no navegador do aparelho.
Future<void> openSite(BuildContext context, [String path = '']) async {
  final base = AppConfig.siteUri;
  if (base == null) {
    showMessage(context, 'O endereço do site não está configurado neste app (SITE_URL).', error: true);
    return;
  }
  final target = path.isEmpty ? base : base.resolve(path);
  final opened = await launchUrl(target, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    showMessage(context, 'Não consegui abrir o navegador.', error: true);
  }
}
