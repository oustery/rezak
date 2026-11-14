# Changelog

Все значимые изменения проекта Rezak документируются в этом файле.
Формат — [Keep a Changelog](https://keepachangelog.com/), версионирование — SemVer.

## 1.1.0 — 2026-11-13

### Добавлено

- **Авто-релиз двух вариантов после компиляции.** CI собирает на каждую
  архитектуру (arm64-v8a, armeabi-v7a) release- и debug-APK — всего четыре
  файла: `rezak-<abi>-v<версия>.apk` и `rezak-<abi>-v<версия>-debug.apk`.
  Оба варианта попадают в GitHub Release на теге и в артефакты workflow на push.
- **Release-подпись в двух режимах.** Если заданы секреты `KEYSTORE_BASE64`,
  `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` — release подписывается
  вашим ключом (стабильная подпись между релизами). Иначе workflow генерирует
  выделенный release-ключ (`keytool`, `CN=Rezak Release`) на время сборки:
  release всегда подписан не debug-ключом.
- **Debug-вариант** подписывается стандартным Android debug-ключом
  (`androiddebugkey` / `android`).
- **Проверка подписей в CI**: `keytool -printcert -jarfile` на обоих APK;
  сборка падает, если release-APК оказался подписан debug-ключом.

### Исправлено

- **Gradle не применял key.properties.** Раньше workflow писал keystore и
  `android/key.properties`, но `build.gradle.kts` их не читал: release всегда
  подписывался debug-ключом даже при заданных секретах, а ветка
  `System.getenv("KEYSTORE_BASE64")` выбирала пустой release-конфиг. Теперь
  `signingConfigs` читает `key.properties` и подписывает release выделенным
  ключом.
- **Версия из тега.** Сборка на теге `v1.1.0` использует `--build-name 1.1.0`;
  раньше на любых тегах ставилась фиксированная `1.0.0`.

## 1.0.0 — 2026-11-13

Первый релиз под новым именем **Rezak** (ранее проект назывался Iframe Saver;
история коммитов не переносилась — чистый старт, ребрендинг полного кода:
имя пакета, applicationId `com.oustery.rezak`, имена APK-артефактов и CI).

### Исправлено (по результатам аудита, docs/AUDIT.md)

- **Проверка звука (B1).** Команда с флагами ffprobe (`-show_entries`, `-of`)
  теперь уходит в `FFprobeKit.executeWithArguments`, а не в `FFmpegKit.execute`:
  ffmpeg таких флагов не знает и раньше всегда падал с «Unrecognized option»,
  из-за чего диалог «Проверить звук» сообщал «Аудио не найдено» на любом файле.
- **Прогресс загрузок (B2).** Колбэк статистики ffmpeg подписан на конкретную
  сессию (`executeWithArgumentsAsync`); прежний глобальный
  `FFmpegKitConfig.enableStatisticsCallback` был один на процесс и при двух
  параллельных загрузках смешивал прогресс задач между собой.
- **CI: подпись релиза (B3).** Условие шага «Подготовка keystore» проверяло
  секрет через env-контекст самого шага, где secrets недоступны, и потому
  никогда не выполнялось — релизы молча подписывались debug-ключом. Флаг
  `KEYSTORE_SET` вычисляется на уровне workflow.
- **Дублирование (B5).** Удалена копия функции форматирования размера файла,
  осталась единственная `humanSize`.

### Добавлено

- **Отмена загрузки (B4).** `DownloadEngine.cancel()` и кнопка «Отменить»
  в карточке активной задачи; в нативном сценарии сессия прерывается
  через `FFmpegKit.cancel(sessionId)`.
- Компоненты **Forui** (`FBadge`, `FButton`) в списке загрузок: статус-бейджи
  и кнопка отмены.
- Лицензия MIT, CHANGELOG, CONTRIBUTING, шаблоны PR и Issue, `.editorconfig`,
  аудит исходного проекта в `docs/AUDIT.md`.
- Ветвление: `master` (стабильная, защищена) и `dev` (разработка);
  CI-проверки на обе ветки.
