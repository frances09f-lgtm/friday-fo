import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ui/screens/home_screen.dart';
import 'ui/screens/settings_screen.dart';

class FridayApp extends StatelessWidget {
  const FridayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Friday',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
      routes: <String, WidgetBuilder>{
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
