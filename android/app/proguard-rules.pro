# R8-правила для release-сборки Rezak.
#
# Flutter-плагины общаются с нативным кодом через JNI и рефлексию: нативная
# сторона ищет Java-классы и методы ПО ИМЕНИ, поэтому R8 не имеет права их
# переименовывать или вырезать, даже если из Dart-кода ссылок не видно.
# Всё остальное (недостижимый код плагинов, старые зависимости) R8 убирает.

# ffmpeg-kit (пакет ffmpeg_kit_flutter_new_https): JNI-мост, нативная
# библиотека libffmpegkit.so вызывает эти классы напрямую. У форка пакет
# переименован в com.antonkarpenko.ffmpegkit; прежнее пространство имён
# оставлено на случай зависимостей со старым именем.
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keep class com.arthenica.ffmpegkit.** { *; }

# flutter_inappwebview: JNI-обёртки WebView и JS-интерфейсы, вызываемые
# из JavaScript через addJavascriptInterface.
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# dartjni (jnigen-мост Flutter): обращается к Java-объектам по имени.
-keep class com.dartjni.** { *; }

# Атрибуты аннотаций нужны JNI-рефлексии.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Предупреждения о отсутствующих классах из опциональных зависимостей
# плагинов не должны ломать сборку.
-dontwarn com.google.android.gms.**
-dontwarn org.chromium.**
