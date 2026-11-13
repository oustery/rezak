// Сборка Android-приложения.
//
// Раздельные APK под архитектуры:
//   flutter build apk --release --target-platform android-arm64   → arm64-v8a
//   flutter build apk --release --target-platform android-arm     → armeabi-v7a
//
// Начиная с Flutter 3.50 флаг --target-platform сам по себе НЕ вырезает
// чужие .so из APK (внутри оказываются arm64-v8a + armeabi-v7a + x86_64).
// Поэтому ABI вырезаем на этапе packaging: оставляем только каталог
// lib/<нужная-abi>/ и их зависимости от ffmpeg тоже попадают только туда.
//
// В CI (.github/workflows/release.yml) обе архитектуры собираются матрицей,
// а шаг «Переименование и проверка ABI» падает, если внутри APK больше
// одной архитектуры, — то есть регрессию такого рода сборка не пропустит.

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            // Подпись: если CI передал keystore (см. workflow) — используем его,
            // иначе debug-ключ, чтобы `flutter build apk --release`
            // работал локально без настройки.
            signingConfig = if (System.getenv("KEYSTORE_BASE64") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
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
