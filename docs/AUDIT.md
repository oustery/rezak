# Аудит исходного репозитория `oustery/iframe-saver` (перед переносом в `rezak`)

Дата аудита: 2026-11-13 · Коммит исходника: `bd08f74` (main, tag `v1.0.0`)

> В процессе переноса все критические находки (B1–B5) исправлены — см. таблицу
> «Статус исправлений» в конце документа и CHANGELOG.md.

---

## 1. Общие сведения

| Параметр | Значение |
|---|---|
| Репозиторий | `oustery/iframe-saver` (приватный, создан 2026-11-13) |
| Ветка по умолчанию | `main` (в новом проекте — `master` + `dev`) |
| История | 6 коммитов, 1 автор, тег `v1.0.0`, 1 Release с двумя APK |
| Issues / PR | 0 / 0 — переносить было нечего |
| Лицензия | отсутствовала — выбрана **MIT** |
| Язык | Dart/Flutter (Android; iOS-папки нет) |
| CI | `pr-check.yml` (формат+анализатор+тесты) и `release.yml` (тесты, APK arm64/armv7 матрицей, релиз на тег) |

**Что это за проект.** Flutter-приложение «Iframe Saver»: по ID Кинопоиска запрашивает список
встраиваемых плееров у агрегатора `iframe.cloud` (API-эндпоинт `https://fbphdplay.top/api/players?kinopoisk=<ID>`),
открывает плеер во встроенном WebView, сниффером перехватывает ссылки на HLS (`.m3u8`) /
DASH (`.mpd`) / MP4, разбирает master-плейлист (качества, отдельная аудиодорожка `#EXT-X-MEDIA`)
и через ffmpeg на устройстве (`ffmpeg_kit_flutter_new`) склеивает видео и звук в один mp4
**без перекодирования** (`-c copy -shortest -movflags +faststart`).

`iframe.cloud` и `fbphdplay.top` — внешние сервисы, **не часть бренда**: при ребрендинге
не изменялись.

## 2. Стек, сборка, зависимости

| Компонент | Версия исходника | Статус |
|---|---|---|
| Flutter SDK | пин 3.50.0 (CI/README) | согласован |
| Dart SDK | `>=3.4.0 <4.0.0` | ок |
| AGP / Gradle / Kotlin | 9.2.1 / 9.5.0 / 2.4.20, Java 17 | согласованная связка |
| `dio` | 5.11.1 | = latest |
| `flutter_inappwebview` | 6.2.0-beta.3 (stable 6.1.5) | осознанная бета — риск |
| `ffmpeg_kit_flutter_new` | 4.6.8 | = latest (форк ffmpeg-kit, GPL) |
| `share_plus` | 10.1.4 (latest 13.3.1) | 2 мажора позади — апгрейд отложен (меняет API шаринга) |
| `path_provider` | 2.1.6 | = latest |
| `material_ui` | 1.11.0 | = latest |
| `flutter_lints` | ^5.0.0 (latest 6.0.0) | на 1 мажор позади — отложено отдельным шагом |
| `forui` (новая) | 0.27.7 | добавлена в rezak: FBadge/FButton в списке загрузок |

Пакет не публикуется (`publish_to: none`) — смена имени не затрагивает внешних потребителей.

## 3. Архитектура

Точка входа `lib/main.dart` → `RezakApp` → `ShellScreen` (IndexedStack: поиск, загрузки).
DI — `AppDependencies` + `InheritedWidget` (`AppScope`); всё внешнее скрыто за интерфейсами
(`PlayersRepository`, `DownloadEngine`, `PlayerWebView`). Модель данных: `PlayerSource`/
`Translation` (ответ API), `DownloadJob` (задача загрузки), `SniffedStream`, `StreamProbeResult`.
Состояние — `AppState extends ChangeNotifier` (in-memory). Критических проблем структуры нет.

## 4. Найденные баги и их статус

| # | Проблема | Серьёзность | Статус |
|---|---|---|---|
| B1 | `probeAudio` отправлял ffprobe-флаги (`-show_entries`, `-of`) в `FFmpegKit.execute` → «Unrecognized option», диалог «Проверить звук» всегда врал | HIGH | ✅ исправлено: `FFprobeKit.executeWithArguments(buildProbeArguments(path))` + тест состава аргументов |
| B2 | Глобальный `FFmpegKitConfig.enableStatisticsCallback` — один на процесс: при 2 параллельных загрузках прогресс смешивался | MED/HIGH | ✅ исправлено: пер-сессийный колбэк через `executeWithArgumentsAsync` |
| B3 | `release.yml`: условие шага подписи `env.KEYSTORE_BASE64` в `if` шага всегда false → релиз молча подписывался debug-ключом | MED | ✅ исправлено: флаг `KEYSTORE_SET` вычисляется на уровне workflow |
| B4 | Отмена загрузки недостижима: статус `cancelled` обработан, но `cancel()` и кнопки нет | MED | ✅ добавлено: `DownloadEngine.cancel()` + кнопка «Отменить» + тест |
| B5 | Дублирование `humanSize` (приватный метод + публичная функция) | LOW | ✅ удалена копия |
| B6 | Оценочный прогресс делится на хардкод «120 минут» | LOW | задокументировано; roadmap: точная длительность через ffprobe |
| B7 | Эвристика `extractKinopoiskId` («последние цифры из любой строки») | LOW | оставлена как UX-эвристика, покрыта тестами |

## 5. Security и приватность

| # | Риск | Оценка | Действие |
|---|---|---|---|
| S1 | `usesCleartextTraffic="true"` глобально | MEDIUM | осознанно (http-сегменты CDN), задокументировано в README |
| S2 | WebView: JS + third-party cookies, навигация не ограничена | LOW | необходимо по сути задачи |
| S3 | Нет LICENSE | HIGH | ✅ MIT |
| S4 | Токены плееров в URL попадают в лог задач | LOW | лог только на устройстве; в шаблоне Issue попросено затирать токены |
| S5 | ffmpeg-аргументы массивом (без shell-инъекций); DRM вне скоупа | — | ок |
| S6 | Keystore через secrets, `key.properties`/`*.jks` в .gitignore | — | ок |

## 6. Ребрендинг (выполнен)

20 файлов / 59 вхождений `iframe_saver`/`Iframe Saver`/`iframe-saver`: pubspec, импорты
`package:rezak/...`, applicationId/namespace `com.oustery.rezak`, каталог `MainActivity.kt`,
label «Rezak», папка вывода, имена APK `rezak-<abi>-v<версия>.apk`, имена релизов,
триггеры CI `[master, dev]`, README. Контроль: `grep -rIiE 'iframe[ _-]?saver'` → 0 вхождений.

## 7. Критерии приёмки переноса

1. ✅ 0 вхождений старого бренда в рабочем дереве.
2. ✅ `dart format --output=none --set-exit-if-changed lib test` — exit 0.
3. ✅ `flutter analyze --no-fatal-infos` — No issues found!
4. ✅ `flutter test` — 83 теста зелёные (79 исходных + 4 на исправления).
5. ⏳ CI зелёный на PR в `dev` и `dev`→`master` (этап 5).
6. ⏳ Ветки `master`+`dev`, дефолт `master`, protection на `master`.
7. ✅ LICENSE, CHANGELOG, CONTRIBUTING, PR/Issue шаблоны, `.editorconfig` на месте.

## 8. Отложенное (roadmap)

- Точная длительность потока через ffprobe → точный прогресс (B6).
- `flutter_lints ^6` и `share_plus 10→13` (последний меняет API шаринга).
- foreground service для фоновых загрузок; очередь и история загрузок (sqflite/hive);
  выбор качества из `StreamProbeResult.variants`; iOS-сборка.
- Замена дефолтной Flutter-иконки на брендированную.
