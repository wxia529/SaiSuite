import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("key.properties")
val releaseKeys = Properties().apply {
    if (signingFile.exists()) signingFile.inputStream().use { load(it) }
}

android {
    buildFeatures { resValues = true }
    namespace = "io.github.wxia529.saisuite"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.wxia529.saisuite"
        resValue("string", "app_name", "赛赛工具箱")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
        if (signingFile.exists()) {
            create("localRelease") {
                storeFile = rootProject.file(releaseKeys.getProperty("storeFile"))
                storePassword = releaseKeys.getProperty("storePassword")
                keyAlias = releaseKeys.getProperty("keyAlias")
                keyPassword = releaseKeys.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "赛赛工具箱（测试）")
        }
        release {
            if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
                require(signingFile.exists()) { "Release requires android/key.properties and the preserved signing keystore." }
            }
            signingConfig = if (signingFile.exists()) signingConfigs.getByName("localRelease") else null
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
    implementation("androidx.media3:media3-transformer:1.11.1")
    implementation("androidx.media3:media3-effect:1.11.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
