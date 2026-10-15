import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.musikku.app"

    // YouTube Player 13.x membutuhkan API modern.
    compileSdk = 36

    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.musikku.app"

        // android-youtube-player minimum API 21.
        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("storeFile")) {
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // R8 rules tambahan untuk referensi java.beans optional dari Rhino/NewPipe.
            // Pertahankan aturan default Android dan gunakan file aplikasi ini.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Pemakaian pribadi: kalau key.properties tidak ada, pakai kunci
            // debug supaya `flutter build apk --release` tetap jalan.
            signingConfig =
                if (keystoreProperties.containsKey("storeFile"))
                    signingConfigs.getByName("release")
                else
                    signingConfigs.getByName("debug")
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
    // NewPipe Extractor: repository is configured in android/build.gradle.kts.
    implementation("com.github.teamnewpipe:NewPipeExtractor:v0.26.5")
    // OkHttp is referenced directly by NewPipeExtractorBridge.kt.
    implementation("com.squareup.okhttp3:okhttp:5.4.0")


    // Explicit AndroidX core dependency used by the native notification bridge.
    implementation("androidx.core:core-ktx:1.17.0")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.4")

    // Pengecekan berkala channel subscribe di latar belakang (notifikasi
    // live / video baru saat aplikasi ditutup).
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // ========================================================
    // NATIVE YOUTUBE PLAYER
    // ========================================================

    implementation(
        "com.pierfrancescosoffritti.androidyoutubeplayer:core:13.0.0"
    )
    implementation(
        "com.pierfrancescosoffritti.androidyoutubeplayer:custom-ui:13.0.0"
    )

    // ========================================================
    // ANDROID MEDIA
    // ========================================================

    implementation(
        "androidx.media:media:1.7.0"
    )

    // ========================================================
    // ANDROIDX MEDIA3
    // ========================================================

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
