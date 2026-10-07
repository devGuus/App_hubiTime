import 'package:flutter/material.dart';

import 'profile_screen.dart';
import 'punch_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Ponto', Icons.schedule_outlined, Icons.schedule),
  _Destination('Relatórios', Icons.bar_chart_outlined, Icons.bar_chart),
  _Destination('Configurações', Icons.tune_outlined, Icons.tune),
  _Destination('Perfil', Icons.person_outline, Icons.person),
];

/// Navegação principal: barra inferior em celulares, trilho lateral em tablets.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // IndexedStack preserva o estado de cada aba (sem recarregar ao alternar).
  late final _pages = const [PunchScreen(), ReportsScreen(), SettingsScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(index: _index, children: _pages);

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
        ],
      ),
    );
  }
}
