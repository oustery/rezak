import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'core/app_dependencies.dart';
import 'screens/shell_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  runApp(RezakApp(dependencies: AppDependencies()));
}

/// Корневой виджет. [dependencies] передаётся снаружи, чтобы в тестах
/// поднять всё приложение на фейковых API/движке загрузки.
class RezakApp extends StatelessWidget {
  const RezakApp({
    super.key,
    required this.dependencies,
    this.animateBackground = true,
  });

  final AppDependencies dependencies;
  final bool animateBackground;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        title: 'Rezak',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: ShellScreen(animateBackground: animateBackground),
      ),
    );
  }
}
