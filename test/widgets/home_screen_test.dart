import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rezak/core/app_dependencies.dart';
import 'package:rezak/screens/home_screen.dart';
import 'package:rezak/ui/theme.dart';
import 'package:rezak/ui/widgets/common.dart';

import '../support/fakes.dart';

/// Оборачивает виджет в MaterialApp + AppScope, как в проде.
Widget _wrap(AppDependencies deps, Widget child) {
  return AppScope(
    dependencies: deps,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    ),
  );
}

/// Прокачивает кадры, пока [finder] не найдётся (максимум ~1 с).
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int tries = 20,
}) async {
  for (var i = 0; i < tries; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw TestFailure('Не дождались: $finder');
}

void main() {
  testWidgets('показывает заголовок и поле ввода с предзаполненным ID',
      (tester) async {
    final deps = buildTestDependencies();
    await tester.pumpWidget(_wrap(deps, const HomeScreen()));
    await tester.pump();

    expect(find.text('Найти плееры'), findsOneWidget);
    expect(find.byKey(const Key('kp-input')), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('kp-input')));
    expect(field.controller?.text, '4640303');
  });

  testWidgets('поиск наполняет список источников', (tester) async {
    final api = FakePlayersRepository();
    await tester.pumpWidget(
      _wrap(buildTestDependencies(api: api), const HomeScreen()),
    );

    await tester.tap(find.byKey(const Key('search-button')));
    await pumpUntilFound(tester, find.textContaining('Turbo'));

    expect(api.requestedIds, ['4640303']);
    expect(find.textContaining('Turbo'), findsOneWidget);
    expect(find.textContaining('Alloha'), findsOneWidget);
    expect(find.text('Источники'), findsOneWidget);
  });

  testWidgets('ошибка API показывается баннером', (tester) async {
    final api = FakePlayersRepository(error: Exception('нет сети'));
    await tester.pumpWidget(
      _wrap(buildTestDependencies(api: api), const HomeScreen()),
    );

    await tester.tap(find.byKey(const Key('search-button')));
    await pumpUntilFound(tester, find.textContaining('Не удалось получить'));

    expect(find.textContaining('Не удалось получить список плееров'),
        findsOneWidget);
    expect(find.byType(MessageBanner), findsOneWidget);
  });

  testWidgets('некорректный ID даёт подсказку и не дергает API',
      (tester) async {
    final api = FakePlayersRepository();
    await tester.pumpWidget(
      _wrap(buildTestDependencies(api: api), const HomeScreen()),
    );

    await tester.enterText(find.byKey(const Key('kp-input')), 'нет-id');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pump();

    expect(find.textContaining('Не вижу числовой ID'), findsOneWidget);
    expect(api.requestedIds, isEmpty);
  });

  testWidgets('мультиозвучка открывает шторку выбора перевода', (tester) async {
    // Высокий «экран», чтобы список источников был виден целиком.
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(buildTestDependencies(), const HomeScreen()),
    );
    await tester.tap(find.byKey(const Key('search-button')));
    await pumpUntilFound(tester, find.textContaining('Alloha'));

    // Тап по источнику с двумя переводами (Alloha)
    await tester.tap(find.textContaining('Alloha'));
    await tester.pumpAndSettle();

    expect(find.text('Выберите озвучку'), findsOneWidget);
    expect(find.textContaining('Русский'), findsOneWidget);
    expect(find.textContaining('Оригинал'), findsOneWidget);
  });

  testWidgets('кнопка поиска блокируется на время запроса', (tester) async {
    final gate = Completer<void>();
    final api = FakePlayersRepository(gate: gate);
    await tester.pumpWidget(
      _wrap(buildTestDependencies(api: api), const HomeScreen()),
    );

    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pump(); // loading = true

    expect(find.text('Ищу плееры…'), findsOneWidget);

    // Второй тап по заблокированной кнопке не должен запускать новый запрос.
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pump();
    expect(api.requestedIds.length, 1);

    gate.complete();
    await pumpUntilFound(tester, find.text('Найти плееры'));
    expect(find.text('Найти плееры'), findsOneWidget);
  });
}
