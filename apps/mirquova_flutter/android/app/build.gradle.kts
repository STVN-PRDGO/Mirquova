import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Android installs an update only when it is signed with the same key as the
// installed app, so every published APK must use this one key. CI supplies it
// through environment variables; local builds read android/key.properties.
val localSigning = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.isFile) file.inputStream().use(::load)
}
val signingStore = System.getenv("MIRQUOVA_KEYSTORE_PATH") ?: localSigning.getProperty("storeFile")
val signingPassword = System.getenv("MIRQUOVA_KEYSTORE_PASSWORD") ?: localSigning.getProperty("password")

android {
    namespace = "dev.mirquova.mirquova"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.mirquova.mirquova"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingStore != null && signingPassword != null) {
            create("mirquova") {
                storeFile = file(signingStore)
                storePassword = signingPassword
                keyAlias = "mirquova"
                keyPassword = signingPassword
            }
        }
    }

    buildTypes {
        val shared = signingConfigs.findByName("mirquova")
        debug {
            if (shared != null) signingConfig = shared
        }
        release {
            signingConfig = shared ?: signingConfigs.getByName("debug")
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
