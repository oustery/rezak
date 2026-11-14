# Rezak

[![Build & Release](https://github.com/oustery/rezak/actions/workflows/release.yml/badge.svg)](https://github.com/oustery/rezak/actions/workflows/release.yml)
[![PR check](https://github.com/oustery/rezak/actions/workflows/pr-check.yml/badge.svg)](https://github.com/oustery/rezak/actions/workflows/pr-check.yml)

Мобильное приложение на **Flutter** для скачивания видео **вместе со звуком** из плееров,
которые отдаёт сервис [iframe.cloud](https://iframe.cloud). Тёмный «glassmorphism»-интерфейс,
83 автотеста и GitHub Actions, собирающий релизные APK под **arm64-v8a** и **armeabi-v7a**.

> ⚠️ Проект учебно-технический. Скачивайте только тот контент, на который у вас есть право
> (собственные записи, свободные лицензии, контент с разрешения правообладателя).
> Автор не несёт ответственности за использование приложения для нарушения авторских прав.

---

## 1. Как это работает

`iframe.cloud` — не видеохостинг, а «переключатель плееров»: по ID фильма он через открытый API
`https://fbphdplay.top/api/players?kinopoisk=<ID>` получает список встраиваемых плееров
(Turbo, Collaps, Alloha, Veoveo, Kodik, Videocdn, Vibix, Hdvb) и показывает выбранный в `<iframe>`.

Видео отдают чужие CDN в адаптивном виде:

* **HLS** — `master.m3u8` + сегменты, звук часто **отдельной дорожкой** (`#EXT-X-MEDIA:TYPE=AUDIO`);
* **DASH** — `manifest.mpd`, где видео и аудио лежат в разных `AdaptationSet`.

Отсюда главная задача приложения: **не просто «скачать ссылку», а собрать видео и аудио в один mp4**.

```
ID Кинопоиска  ──▶  API плееров  ──▶  WebView + сниффер  ──▶  ffmpeg (копирование потоков)
  4640303           fbphdplay.top       перехват m3u8/mpd        видео + звук в одном файле
```

---

## 2. Дизайн

Тёмная тема, живой градиентный фон (`AuroraBackground` на `CustomPainter`), «стеклянные»
карточки (`FrostedPanel` + `BackdropFilter`), градиентные CTA-кнопки с тактильным откликом,
нижняя навигация-«пилюля», статус-чипы и моноширинные блоки для команд/логов.

Вся система в одном месте — `lib/ui/theme.dart`:

| Токен | Значение |
|---|---|
| Фон | `#05070E`, поверхности `#0E1422` / `#141C2E` |
| Акцент | `#35E1FF` → `#5B8CFF` (градиент действия) |
| Доп. акценты | `#FF5C8A` (розовый), `#B7FF7A` (успех), `#FFC857` (предупреждение) |
| Радиусы | карточки 22, контролы 16, «пилюли» 100 |
| Типографика | display 30/800, title 19/700, body 14/1.45, mono 11.5 |

Материал — `material_ui` (в Flutter 3.47+ `package:flutter/material.dart` помечен deprecated),
тема `useMaterial3: true`, `ColorScheme.fromSeed` в тёмном варианте. Часть контролов списка
загрузок (статус-бейджи, кнопка отмены) собрана на компонентах
[Forui](https://pub.dev/packages/forui) в его тёмной теме.

---

## 3. Возможности

| Возможность | Где в коде |
|---|---|
| Поиск плееров по ID или по ссылке `https://iframe.cloud/see/ID` | `lib/services/players_api.dart` |
| Выбор источника и озвучки (у Alloha/Collaps их бывает 2+) | `lib/screens/home_screen.dart` |
| WebView со **сниффером**: сам находит `.m3u8` / `.mpd` / `.mp4`, отсекает сегменты | `lib/services/sniffer.dart`, `lib/ui/player_web_view.dart` |
| Разбор master-плейлиста: качества + **явно показывает, где аудио** | `lib/services/manifest_parser.dart` |
| Скачивание с `Referer`/`User-Agent` и склейка видео+аудио **без перекодирования** | `lib/services/download_service.dart` |
| Ручной ввод ссылок (video + отдельный audio) | кнопка 🔗 в экране плеера |
| Прогресс, шаринг файла, **проверка наличия звука через ffprobe** | `lib/screens/downloads_screen.dart` |
| **Отмена активной загрузки** кнопкой в карточке | `DownloadEngine.cancel` → `FFmpegKit.cancel` |

### Ключевая деталь — команда ffmpeg

Именно из-за неё файлы обычно получаются «немыми»: берут только видеопоток.

```bash
ffmpeg -user_agent "<UA>" -headers "Referer: https://iframe.cloud/" \
       -i "<master.m3u8>" \
       -map 0:v:0 -map 0:a:0 \
       -c copy -shortest -movflags +faststart out.mp4
```

* `-map 0:v:0 -map 0:a:0` — первый видеопоток **и** первая аудиодорожка;
* если звук в отдельном плейлисте — второй вход и `-map 1:a:0`;
* `-c copy` — без перекодирования (быстро, качество 1:1);
* `-shortest` — страховка от расхождения длительностей потоков HLS;
* `+faststart` — `moov` в начало файла.

Реализация: `DownloadService.buildFfmpegArguments()`; состав аргументов покрыт тестами.

---

## 4. Тесты

```bash
flutter test                 # 83 теста
flutter test --coverage      # + покрытие в coverage/lcov.info
```

| Файл | Что проверяет |
|---|---|
| `test/manifest_parser_test.dart` | извлечение ID из ссылок разных видов, HLS master с аудиогруппой и без, несколько озвучек, IGNORE `SUBTITLES`, DASH, HTML-заглушка, относительные URI |
| `test/sniffer_test.dart` | перехват `m3u8`/`mpd`/`mp4`, отсечение `.ts`/`.m4s`, дедупликация, события стрима, `shortUrl` |
| `test/players_api_test.dart` | парсинг ответа API на подменённом транспорте Dio, сортировка источников, ошибки, query-параметры |
| `test/download_service_test.dart` | **состав ffmpeg-команды**, успех/ошибка/отмена, «успех без файла», санитайзинг имени, лимит параллельности, `probeAudio`, `humanSize`, `buildProbeArguments`, `cancel` |
| `test/app_state_test.dart` | `upsert`, счётчики, `clearFinished`, защита от мутации списка |
| `test/widgets/home_screen_test.dart` | заголовки, поиск, баннер ошибки, валидация ID, шторка озвучек, блокировка кнопки во время запроса |
| `test/widgets/player_screen_test.dart` | пустое состояние сниффера, появление потока, шторка «аудио найдено / не найдено», ошибка чтения плейлиста, запуск движка, ручной ввод |
| `test/widgets/downloads_screen_test.dart` | пустое состояние, сводка, прогресс-бар, шаринг, диалог проверки звука (есть/нет аудио), очистка, лог ошибки, отмена активной задачи |
| `test/widgets/app_smoke_test.dart` | запуск всего приложения, переключение вкладок, тема, статичный фон |

Для тестируемости всё внешнее спрятано за интерфейсами (`test/support/fakes.dart`):
`PlayersRepository` (API), `DownloadEngine` (ffmpeg), `PlayerWebView` (WebView), `AppState`
(хранилище). Поэтому тесты не ходят в сеть и не требуют нативных библиотек.

---

## 5. CI: авто-релиз release и debug APK под arm64 и armv7

`.github/workflows/release.yml` — три задачи:

1. **Analyze & test** — `flutter analyze` + `flutter test`;
2. **build-apk** — матрица из двух архитектур, в каждой собираются **оба варианта**:

   | ABI | Вариант | Артефакт | Подпись |
   |---|---|---|---|
   | `arm64-v8a` | release | `rezak-arm64-v8a-v<версия>.apk` | выделенный release-ключ |
   | `arm64-v8a` | debug | `rezak-arm64-v8a-v<версия>-debug.apk` | стандартный Android debug-ключ |
   | `armeabi-v7a` | release | `rezak-armeabi-v7a-v<версия>.apk` | выделенный release-ключ |
   | `armeabi-v7a` | debug | `rezak-armeabi-v7a-v<версия>-debug.apk` | стандартный Android debug-ключ |

   После сборки workflow **проверяет** каждый APK: ровно одна архитектура и именно
   ожидаемая (через `unzip -l | grep lib/`), затем подписи (`keytool -printcert -jarfile`) —
   release-APK обязан быть подписан **не** debug-ключом. Только после этого файлы
   переименовываются и публикуются.
3. **publish** — на тег `v*` создаёт GitHub Release и прикрепляет все четыре APK;
   versionName берётся из тега (`v1.1.0` → `1.1.0`).

Триггеры: push в `master`/`dev` (артефакты без релиза), тег `v*` (релиз), PR (проверка
и сборка всех вариантов), ручной запуск с параметром `build_name`. Отдельный `pr-check.yml`
дополнительно проверяет `dart format --set-exit-if-changed`.

**Release-подпись, два режима.** Если в секретах репозитория заданы `KEYSTORE_BASE64`,
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` — release подписывается вашим ключом:
подпись стабильна между релизами, APK обновляются поверх друг друга. Иначе CI **генерирует**
выделенный release-ключ (`keytool`, `CN=Rezak Release`) на время сборки: release-APK
подписан не debug-ключом, но ключ живёт только в рамках запуска — подпись между сборками
меняется, и обновление поверх предыдущей версии может потребовать переустановку.
Для стабильной подписи задайте секреты.

**Debug-вариант** всегда подписан стандартным Android debug-ключом (`androiddebugkey` /
`android`) и предназначен для тестов; ставить его рядом с release нельзя — один applicationId.

**Оптимизация размера.** Release собирается «худым»: ffmpeg-кит — вариант
`ffmpeg_kit_flutter_new_https` (минимальная сборка + gnutls) вместо full-gpl —
приложению нужен только ремюкс `-c copy` и ffprobe, кодеки x264/x265 не
используются; Java/Kotlin-код плагинов прогоняется через R8 с shrinkResources
(`android/app/proguard-rules.pro` защищает JNI-слои ffmpeg-kit и WebView);
Dart-код обфусцируется (`--obfuscate`), символы выносятся в артефакт workflow
`rezak-symbols-<abi>` — стектрейсы release расшифровываются через `flutter symbolize`.
Debug-вариант не минифицируется и не обфусцируется — он для отладки.

Локально то же самое:

```bash
flutter pub get
flutter test
flutter build apk --release --target-platform android-arm64   # arm64-v8a
flutter build apk --debug   --target-platform android-arm     # armeabi-v7a (debug)
```

Локально, без `android/key.properties`, release подписывается debug-ключом — для
разработки этого достаточно; CI всегда выпускает release с выделенной подписью.

---

## 6. Запуск из исходников

```bash
flutter pub get
flutter run            # на подключённом телефоне/эмуляторе
flutter build apk --release --target-platform android-arm64
```

Требования: Flutter **3.50+**, JDK 17, Android SDK 21+. Папка `android/` уже в репозитории;
iOS-папки нет — при необходимости `flutter create --platforms=ios .`.

Зависимости: `dio` (API и чтение плейлиста), `flutter_inappwebview` (WebView со сниффером),
`ffmpeg_kit_flutter_new_https` (ffmpeg/ffprobe на устройстве — поддерживаемый форк
вышедшего на пенсию `ffmpeg-kit`, вариант «минимальный + TLS»: ремюкс и проверка
потоков без тяжёлых кодеков), `path_provider`, `share_plus`, `material_ui`.

---

## 7. Ограничения

1. **Регион и IP.** Плееры режут по региону: при проверке API с сервера в датацентре Alloha
   и Collaps отвечали `403` / «недоступно для вашего региона: US», хотя из браузера в BY
   те же ссылки работают. VPN может как помочь, так и помешать.
2. **Токены живут недолго.** `iframeUrl` содержит `token`/`token_movie` или JWT с `exp`;
   протухшие ссылки надо снимать заново.
3. **DRM.** Поток с Widevine/PlayReady приложение открыть не сможет.
4. **Отдельный аудиоплейлист без `#EXT-X-MEDIA`.** Приложение предупредит в шторке
   «Параметры загрузки» — тогда ссылку на аудио нужно подставить вторым полем вручную.
5. **Нет foreground service:** при сворачивании Android может прибить загрузку.

## 8. Что дальше

* foreground service (`flutter_foreground_task`) для фоновых загрузок;
* `ffprobe` перед стартом → точный прогресс вместо оценочного;
* очередь загрузок и сохранение истории (`sqflite`/`hive`);
* выбор качества из разобранного master-плейлиста (`StreamProbeResult.variants` уже есть);
* iOS-сборка и экспорт в «Фото» через `photo_manager`.

---

## 9. Структура

```
lib/
├── main.dart                     # точка входа, тема, AppScope
├── core/app_dependencies.dart     # сборка зависимостей + InheritedWidget
├── models/player_source.dart      # PlayerSource / Translation
├── services/
│   ├── players_api.dart           # GET /api/players + парсинг ID
│   ├── sniffer.dart               # перехват m3u8/mpd/mp4
│   ├── manifest_parser.dart       # HLS/DASH: качества и аудиодорожки
│   └── download_service.dart      # ffmpeg-команды, запуск, ffprobe
├── state/app_state.dart           # список загрузок (ChangeNotifier)
├── ui/
│   ├── theme.dart                 # палитра, типографика, тема
│   ├── player_web_view.dart       # абстракция WebView (для тестов)
│   └── widgets/                   # aurora-фон, glass-карточки, кнопки
└── screens/
    ├── shell_screen.dart          # навигация-«пилюля»
    ├── home_screen.dart           # поиск по ID, источники, озвучки
    ├── player_screen.dart         # WebView + сниффер + шторка загрузки
    └── downloads_screen.dart      # прогресс, шаринг, проверка звука
```

---

## 10. Ветки и релизы

* `master` — стабильная ветка, защищена: изменения только через PR из `dev`;
* `dev` — разработка: feature-ветки (`feat/...`, `fix/...`) → PR в `dev` (squash);
* `dev` → `master` — merge-коммитом; тег `v*` на `master` запускает сборку
  релизных APK и создаёт GitHub Release (`rezak-<abi>-v<версия>.apk`).
* Процесс и правила коммитов — [CONTRIBUTING.md](CONTRIBUTING.md).

## 11. История и лицензия

Проект развился из `oustery/iframe-saver`: при переносе выполнен ребрендинг
(имя пакета, applicationId `com.oustery.rezak`, имена артефактов и CI), история
коммитов не переносилась — чистый старт. Результаты аудита исходного проекта
и статусы исправлений — в [docs/AUDIT.md](docs/AUDIT.md), хронология изменений —
в [CHANGELOG.md](CHANGELOG.md).

Лицензия — [MIT](LICENSE).
