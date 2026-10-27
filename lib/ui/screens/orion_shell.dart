import 'package:flutter/material.dart';
import '../stitch_style.dart';
import '../friday_motion.dart';
import 'agent_mode_screen.dart';
import 'background_tasks_screen.dart';
import 'device_link_screen.dart';
import 'home_screen.dart';
import 'immersive_voice_screen.dart';
import 'notifications_screen.dart';
import '../../update/app_update.dart';
/// Five lazy, retained tabs. Motion never creates another service or page.
class OrionShell extends StatefulWidget {
 const OrionShell({super.key, required this.onToggleTheme});
 final VoidCallback onToggleTheme;
 @override State<OrionShell> createState() => _OrionShellState();
}
class _OrionShellState extends State<OrionShell> {
 int tab = 0; final Set<int> built = {0};
 @override void initState() {
  super.initState();
  // In-app self-update: check the latest release once after the first frame
  // (at most every 6 hours; skipped in tests).
  WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) maybePromptUpdate(context); });
 }
 void select(int i) { if (i == tab) return; setState(() { tab = i; built.add(i); }); }
 Widget page(int i) {
  switch (i) {
   case 0: return const HomeScreen(showHeader: false);
   case 1: return const AgentModeScreen();
   case 2: return BackgroundTasksScreen(embedded: true, onCreate: () => select(0));
   case 3: return const NotificationsScreen();
   default: return const DeviceLinkScreen();
  }
 }
 @override Widget build(BuildContext context) {
  final theme = Theme.of(context); final scheme = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
  Widget icon(IconData data, int i) => AnimatedScale(scale: tab == i ? 1.12 : 1, duration: FridayMotion.duration(context, FridayMotion.toggle), curve: FridayMotion.spring, child: Icon(data));
  return Scaffold(
   appBar: AppBar(titleSpacing: 20, title: Row(children: [const CoreLogo(size: 28), const SizedBox(width: 12), Flexible(child: Text('Friday', maxLines: 1, overflow: TextOverflow.ellipsis, style: Stitch.title(24)))]), actions: [
    MotionPress(scale: .88, child: IconButton(tooltip: 'Voice session', onPressed: () => Navigator.push(context, MotionRoute(builder: (_) => const ImmersiveVoiceScreen())), icon: const Icon(Icons.graphic_eq))),
    MotionPress(scale: .88, child: IconButton(tooltip: dark ? 'Light theme' : 'Dark theme', onPressed: widget.onToggleTheme, icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined))),
    MotionPress(scale: .90, child: IconButton(tooltip: 'Settings', onPressed: () => Navigator.pushNamed(context, '/settings'), icon: const Icon(Icons.settings_outlined))), const SizedBox(width: 4)
   ]),
   body: IndexedStack(index: tab, children: [for (var i = 0; i < 5; i++) built.contains(i) ? MotionTab(key: ValueKey('tab-$i'), active: tab == i, child: page(i)) : const SizedBox.shrink()]),
   bottomNavigationBar: keyboard ? null : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), child: DecoratedBox(decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(32)), child: ClipRRect(borderRadius: BorderRadius.circular(32), child: LayoutBuilder(builder: (c, constraints) {
    final slot = constraints.maxWidth / 5; final width = slot < 56 ? slot - 4 : 56.0;
    final selected = Directionality.of(c) == TextDirection.rtl ? 4 - tab : tab;
    return Stack(children: [
     AnimatedPositioned(duration: FridayMotion.duration(c, FridayMotion.dock), curve: FridayMotion.spring, left: slot * selected + (slot - width) / 2, top: 8, width: width, height: 32,
      child: IgnorePointer(child: ExcludeSemantics(child: TweenAnimationBuilder<double>(key: ValueKey('pill-$tab'), tween: Tween(begin: .35, end: 1), duration: FridayMotion.duration(c, FridayMotion.dock), curve: FridayMotion.spring,
       builder: (c, v, _) => Transform.scale(scaleX: v, scaleY: 1, child: DecoratedBox(key: const ValueKey('selected-dock-pill'), decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)))))))),
     NavigationBar(height: 68, backgroundColor: Colors.transparent, indicatorColor: Colors.transparent, selectedIndex: tab, animationDuration: FridayMotion.duration(c, FridayMotion.toggle), onDestinationSelected: select, destinations: [
      NavigationDestination(icon: icon(Icons.chat_bubble_outline, 0), selectedIcon: icon(Icons.chat_bubble, 0), label: 'Chat'),
      NavigationDestination(icon: icon(Icons.smart_toy_outlined, 1), selectedIcon: icon(Icons.smart_toy, 1), label: 'Agent'),
      NavigationDestination(icon: icon(Icons.checklist_rounded, 2), label: 'Tasks'),
      NavigationDestination(icon: icon(Icons.notifications_outlined, 3), selectedIcon: icon(Icons.notifications, 3), label: 'Alerts'),
      NavigationDestination(icon: icon(Icons.devices_other_outlined, 4), selectedIcon: icon(Icons.devices_other, 4), label: 'Devices'),
     ])
    ]);
   }))))));
 }
}
