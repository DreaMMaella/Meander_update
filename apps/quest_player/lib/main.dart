import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_core/mnd_core.dart' show initRustCore;
import 'package:mnd_player/services/mnd_player_bootstrap.dart';

import 'quest_player_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initRustCore();
  MndPlayerBootstrap.initialize(debugLogs: kDebugMode);

  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const ProviderScope(child: QuestPlayerApp()));
}
