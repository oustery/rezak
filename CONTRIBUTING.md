# Contributing

Спасибо за интерес к проекту. Коротко о том, как в нём устроен процесс.

## Ветки

* `master` — стабильная ветка. Изменения попадают в неё **только** через
  PR из `dev`; ветка защищена (Branch Protection).
* `dev` — ветка разработки.
* Feature-ветки: `feat/краткое-имя`, `fix/краткое-имя` — создаются от `dev`.

## Слияния

* feature → `dev`: **squash** (один коммит на PR);
* `dev` → `master`: **merge-коммит** (сохраняет историю релизных циклов);
* тег `v*`, поставленный на `master`, запускает сборку релизных APK
  и создаёт GitHub Release.

## Коммиты

Conventional Commits допустимы, описания на русском, как в остальной истории:
`feat:`, `fix:`, `build:`, `ci:`, `docs:`, `refactor:`, `chore:`.

Не коммитьте: секреты, `*.jks`/keystore, артефакты сборки, `node_modules`,
`.dart_tool/`. Всё нужное уже в `.gitignore`.

## Локальные проверки перед PR

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test
```

CI (`pr-check.yml` и тестовая задача `release.yml`) выполняет ровно эти же
шаги, поэтому зелёный локальный прогон — почти гарантированно зелёный PR.

## Тесты

Всё внешнее (API, ffmpeg, WebView, файловая система) скрыто за интерфейсами
(`lib/services/download_service.dart`, `lib/services/players_api.dart`,
`lib/ui/player_web_view.dart`), подмены лежат в `test/support/fakes.dart`.
Изменяя логику загрузки/поиска, добавляйте тесты в те же файлы, где живёт
существующее покрытие.

## Сообщения об ошибках

Используйте шаблоны Issue («Баг», «Идея функциональности») — так в запросе
сразу окажутся версия APK, устройство и шаги воспроизведения.
