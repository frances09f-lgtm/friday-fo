import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'assistant_overlay.dart' as overlay;
import 'friday_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await createFridayServices();
  runApp(
    MultiProvider(
      providers: services.providers,
      child: const FridayApp(),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> assistantOverlayMain() => overlay.assistantOverlayMain();
