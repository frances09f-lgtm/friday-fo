import 'package:flutter/material.dart';
import 'ui/stitch_style.dart';

import 'ui/screens/command_center_screen.dart';
import 'ui/screens/settings_screen.dart';

class FridayApp extends StatelessWidget {
  const FridayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Friday',
      debugShowCheckedModeBanner: false,
      theme: Stitch.theme(),
      home: const CommandCenterScreen(),
      routes: <String, WidgetBuilder>{
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
