import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui/orion_style.dart';
import 'ui/friday_motion.dart';
import 'ui/motion_transitions.dart';
import 'ui/screens/orion_shell.dart';
import 'ui/screens/settings_screen.dart';

/// Theme persistence is unchanged. Settings uses the measured overlay motion.
class OrionApp extends StatefulWidget {
  const OrionApp({super.key});
  @override
  State<OrionApp> createState() => _OrionAppState();
}
class _OrionAppState extends State<OrionApp> {
  static const _key = 'orion_theme_mode';
  ThemeMode mode = ThemeMode.system;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (!mounted) return;
      if (saved == 'light' || saved == 'dark') setState(() => mode = saved == 'dark' ? ThemeMode.dark : ThemeMode.light);
    } catch (_) {}
  }
  Future<void> _toggle() async {
    final systemDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final isDark = mode == ThemeMode.dark || (mode == ThemeMode.system && systemDark);
    final next = isDark ? ThemeMode.light : ThemeMode.dark;
    setState(() => mode = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, next == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Friday', debugShowCheckedModeBanner: false,
    theme: withFridayMotion(Orion.light()), darkTheme: withFridayMotion(Orion.dark()), themeMode: mode,
    home: OrionShell(onToggleTheme: _toggle),
    onGenerateRoute: (settings) => settings.name == '/settings'
      ? MotionRoute<void>(settings: settings, builder: (_) => const SettingsScreen()) : null);
}
