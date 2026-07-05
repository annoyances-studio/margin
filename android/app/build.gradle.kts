import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing reads from android/key.properties (gitignored). Absent (e.g.
// CI or a fresh clone) → the build falls back to debug signing below, so it
// still works; present → the release build is signed with your upload key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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
        // Distributable app id (Annoyances Studio namespace). Kept distinct from
        // the internal `namespace` (com.lordofthedummies.margin), which is fine —
        // this is what Play, Entra/OneDrive, and Google dev-verification key on.
        applicationId = "studio.annoyances.margin"
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

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the release keystore when key.properties is present; fall back
            // to debug signing until it exists so builds keep working.
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
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
