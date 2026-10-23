import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'assistant_overlay.dart' as overlay;
import 'friday_services.dart';
import 'orion_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await createFridayServices();
  runApp(
    MultiProvider(
      providers: services.providers,
      child: const OrionApp(),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> assistantOverlayMain() => overlay.assistantOverlayMain();
