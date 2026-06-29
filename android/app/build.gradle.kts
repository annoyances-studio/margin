plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.lordofthedummies.margin"
    // Pinned above flutter.compileSdkVersion: several plugins (file_selector,
    // flutter_secure_storage, shared_preferences, url_launcher — bumped when
    // desktop_drop was added) require compiling against Android SDK 36.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lordofthedummies.margin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // OneDrive OAuth: tell flutter_appauth which URI scheme to register
        // intent filters for, so the system browser can hand the redirect
        // (msauth://com.lordofthedummies.margin/<sigHash>) back to the app.
        // The package's own RedirectUriReceiverActivity declaration is then
        // complete — including the transparent theme that prevents the brief
        // "blank screen" while the receiver activity finishes itself.
        manifestPlaceholders["appAuthRedirectScheme"] = "msauth"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
