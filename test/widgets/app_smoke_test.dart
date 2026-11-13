import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rezak/main.dart';
import 'package:rezak/screens/downloads_screen.dart';
import 'package:rezak/screens/home_screen.dart';
import 'package:rezak/ui/theme.dart';
import 'package:rezak/ui/widgets/aurora_background.dart';

import '../support/fakes.dart';

/// Дымовой тест всего приложения: поднимаем реальный RezakApp
/// на фейковых зависимостях.
void main() {
  testWidgets('приложение стартует на вкладке поиска', (tester) async {
    final deps = buildTestDependencies();

    await tester.pumpWidget(
      RezakApp(dependencies: deps, animateBackground: false),
    );
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Видео и звук —\nв одном файле'), findsOneWidget);
    expect(find.byType(AuroraBackground), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('переключение вкладок: поиск ↔ загрузки', (tester) async {
    final deps = buildTestDependencies();

    await tester.pumpWidget(
      RezakApp(dependencies: deps, animateBackground: false),
    );
    await tester.pump();

    await tester.tap(find.text('Загрузки'));
    await tester.pumpAndSettle();

    expect(find.byKey(DownloadsKeys.empty), findsOneWidget);

    await tester.tap(find.text('Поиск'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kp-input')), findsOneWidget);
  });

  testWidgets('тема: тёмная схема и кастомный шрифт заголовков',
      (tester) async {
    final deps = buildTestDependencies();

    await tester.pumpWidget(
      RezakApp(dependencies: deps, animateBackground: false),
    );
    await tester.pump();

    final context = tester.element(find.byType(HomeScreen));
    final theme = Theme.of(context);

    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.textTheme.displaySmall?.fontWeight, FontWeight.w800);
    expect(theme.useMaterial3, isTrue);
  });

  testWidgets('фон-градиент рендерится без анимации (статичный кадр)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuroraBackground(
          animate: false,
          child: Scaffold(body: Text('контент')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('контент'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    // без animate контроллер не запущен — лишних кадров не будет
    await tester.pump(const Duration(seconds: 5));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
