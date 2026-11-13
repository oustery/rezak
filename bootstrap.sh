#!/usr/bin/env bash
# bootstrap.sh — первичная настройка проекта на новой машине.
#
# В репозитории лежит только Dart-код и Android-обвязка (android/).
# iOS-платформа генерируется локально, чтобы не тащить в git
# машинно-зависимые файлы.
#
# Требования: Flutter SDK >= 3.50 в PATH, JDK 17, Android SDK.

set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null; then
  echo "Не найден flutter в PATH. Установите SDK: https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

echo "==> Версия Flutter"
flutter --version | head -n 1

if [ ! -d ios ]; then
  echo "==> Генерирую iOS-папку (android уже в репозитории)"
  flutter create --platforms=ios --org com.oustery --project-name rezak .
fi

echo "==> Зависимости"
flutter pub get

echo "==> Тесты"
flutter test

echo
echo "Готово. Дальше:"
echo "  flutter run                                                   # запуск на устройстве"
echo "  flutter build apk --release --target-platform android-arm64    # arm64-v8a"
echo "  flutter build apk --release --target-platform android-arm      # armeabi-v7a"
