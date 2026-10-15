import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        f.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.musikku.app"

    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.musikku.app"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("storeFile")) {
                storeFile = rootProject.file(
                    keystoreProperties["storeFile"] as String
                )

                storePassword =
                    keystoreProperties["storePassword"] as String

                keyAlias =
                    keystoreProperties["keyAlias"] as String

                keyPassword =
                    keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Diagnosis crash WorkManager/Room pada build release.
            // Nonaktifkan optimasi kode dan resource shrinking.
            isMinifyEnabled = false
            isShrinkResources = false

            proguardFiles(
                getDefaultProguardFile(
                    "proguard-android-optimize.txt"
                ),
                "proguard-rules.pro"
            )

            // Gunakan signing release jika key.properties tersedia.
            // Jika tidak, gunakan debug signing untuk build lokal.
            signingConfig =
                if (keystoreProperties.containsKey("storeFile")) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget =
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // YouTube extraction
    implementation(
        "com.github.teamnewpipe:NewPipeExtractor:v0.26.5"
    )

    implementation("com.squareup.okhttp3:okhttp:5.4.0")

    // AndroidX Core
    implementation("androidx.core:core-ktx:1.17.0")

    // Java API desugaring
    coreLibraryDesugaring(
        "com.android.tools:desugar_jdk_libs_nio:2.1.4"
    )

    // Background tasks and notifications
    implementation(
        "androidx.work:work-runtime-ktx:2.9.1"
    )

    // Native YouTube player
    implementation(
        "com.pierfrancescosoffritti.androidyoutubeplayer:core:13.0.0"
    )

    implementation(
        "com.pierfrancescosoffritti.androidyoutubeplayer:custom-ui:13.0.0"
    )

    // Android media
    implementation("androidx.media:media:1.7.0")

    // AndroidX Media3
    implementation(
        "androidx.media3:media3-exoplayer:1.8.0"
    )

    implementation(
        "androidx.media3:media3-common:1.8.0"
    )
}

flutter {
    source = "../.."
}