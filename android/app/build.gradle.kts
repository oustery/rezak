// Сборка Android-приложения.
//
// Раздельные APK под архитектуры (release и debug):
//   flutter build apk --release --target-platform android-arm64   → arm64-v8a
//   flutter build apk --release --target-platform android-arm     → armeabi-v7a
//   flutter build apk --debug   --target-platform android-arm64   → arm64-v8a (debug)
//
// Начиная с Flutter 3.50 флаг --target-platform сам по себе НЕ вырезает
// чужие .so из APK (внутри оказываются arm64-v8a + armeabi-v7a + x86_64).
// Поэтому ABI вырезаем на этапе packaging: оставляем только каталог
// lib/<нужная-abi>/ и их зависимости от ffmpeg тоже попадают только туда.
//
// В CI (.github/workflows/release.yml) обе архитектуры собираются матрицей,
// а шаг «Переименование и проверка ABI» падает, если внутри APK больше
// одной архитектуры, — то есть регрессию такого рода сборка не пропустит.

import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Подпись release-сборки читается из android/key.properties (файл в .gitignore).
// Его создаёт CI: либо из секретов репозитория (KEYSTORE_*), либо рядом лежит
// сгенерированный на время сборки release-ключ (rezak-release.jks). Без
// key.properties release подписывается debug-ключом — локальная сборка
// работает без настройки.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Какая ABI запрошена сборкой (Flutter передаёт -Ptarget-platform=...).
val requestedPlatform: String =
    (project.findProperty("target-platform") as String?)?.trim().orEmpty()

val abiFilters: Set<String> = when (requestedPlatform) {
    "android-arm64" -> setOf("arm64-v8a")
    "android-arm" -> setOf("armeabi-v7a")
    "android-x64" -> setOf("x86_64")
    else -> emptySet() // универсальный APK
}

android {
    namespace = "com.oustery.rezak"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.oustery.rezak"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // 1000 * ABI + versionCode — как рекомендует Flutter для split APK.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Оставляем в APK только запрошенную архитектуру.
    packaging {
        jniLibs {
            if (abiFilters.isNotEmpty()) {
                val all = setOf(
                    "lib/arm64-v8a/**",
                    "lib/armeabi-v7a/**",
                    "lib/x86/**",
                    "lib/x86_64/**",
                )
                val keep = abiFilters.map { "lib/$it/**" }.toSet()
                excludes += all - keep
            }
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("rezakRelease") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // CI кладёт android/key.properties (ключ из секретов либо
            // сгенерированный release-ключ) → подписываем выделенным
            // release-ключом; без файла — debug-ключ, чтобы локальная
            // `flutter build apk --release` работала без настройки.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("rezakRelease")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8: вырезание неиспользуемого Java/Kotlin-кода и ресурсов
            // плагинов (classes.dex в full-сборке занимал ~8.6 МБ).
            // Правила в proguard-rules.pro защищают JNI-слои плагинов.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
