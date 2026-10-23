import 'package:flutter/material.dart';

import '../stitch_style.dart';
import 'agent_mode_screen.dart';
import 'background_tasks_screen.dart';
import 'device_link_screen.dart';
import 'home_screen.dart';
import 'immersive_voice_screen.dart';
import 'notifications_screen.dart';

/// Orion Store shell: header with theme toggle and a plain gear for Settings,
/// five tabs in a pill dock. Each tab is built the first time it is opened.
class OrionShell extends StatefulWidget {
  const OrionShell({super.key, required this.onToggleTheme});
  final VoidCallback onToggleTheme;
  @override
  State<OrionShell> createState() => _OrionShellState();
}

class _OrionShellState extends State<OrionShell> {
  int tab = 0;
  final Set<int> built = {0};

  void select(int i) => setState(() {
        tab = i;
        built.add(i);
      });

  Widget page(int i) {
    switch (i) {
      case 0:
        return const HomeScreen(showHeader: false);
      case 1:
        return const AgentModeScreen();
      case 2:
        return BackgroundTasksScreen(embedded: true, onCreate: () => select(0));
      case 3:
        return const NotificationsScreen();
      default:
        return const DeviceLinkScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
          titleSpacing: 20,
          title: Row(children: [
            const CoreLogo(size: 28),
            const SizedBox(width: 12),
            Text('Friday', style: Stitch.title(24)),
          ]),
          actions: [
            IconButton(
                tooltip: 'Voice session',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ImmersiveVoiceScreen())),
                icon: const Icon(Icons.graphic_eq)),
            IconButton(
                tooltip: dark ? 'Light theme' : 'Dark theme',
                onPressed: widget.onToggleTheme,
                icon: Icon(
                    dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined)),
            IconButton(
                tooltip: 'Settings',
                onPressed: () => Navigator.pushNamed(context, '/settings'),
                icon: const Icon(Icons.settings_outlined)),
            const SizedBox(width: 4),
          ]),
      body: IndexedStack(index: tab, children: [
        for (var i = 0; i < 5; i++)
          built.contains(i) ? page(i) : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: keyboard
          ? null
          : SafeArea(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(32)),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: NavigationBar(
                              selectedIndex: tab,
                              onDestinationSelected: select,
                              destinations: const [
                                NavigationDestination(
                                    icon: Icon(Icons.chat_bubble_outline),
                                    selectedIcon: Icon(Icons.chat_bubble),
                                    label: 'Chat'),
                                NavigationDestination(
                                    icon: Icon(Icons.smart_toy_outlined),
                                    selectedIcon: Icon(Icons.smart_toy),
                                    label: 'Agent'),
                                NavigationDestination(
                                    icon: Icon(Icons.checklist_rounded),
                                    label: 'Tasks'),
                                NavigationDestination(
                                    icon: Icon(Icons.notifications_outlined),
                                    selectedIcon: Icon(Icons.notifications),
                                    label: 'Alerts'),
                                NavigationDestination(
                                    icon: Icon(Icons.devices_other_outlined),
                                    selectedIcon: Icon(Icons.devices_other),
                                    label: 'Devices'),
                              ]))))),
    );
  }
}
