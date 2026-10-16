import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keyPropertiesFile.exists()) {
        keyPropertiesFile.inputStream().use { load(it) }
    }
}

val requiredReleaseSigningProperties = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val releaseSigningConfigured = requiredReleaseSigningProperties.all { key ->
    !keystoreProperties.getProperty(key).isNullOrBlank()
}
val releaseKeystoreFile = if (releaseSigningConfigured) {
    rootProject.file(keystoreProperties.getProperty("storeFile"))
} else {
    null
}

// Verify production signing through release packaging tasks instead of
// Gradle's taskGraph.whenReady closure. This is compatible with Kotlin DSL
// and still covers assembleRelease, bundleRelease, packageRelease, and
// validateSigningRelease (including aggregate tasks that depend on them).
val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    group = "verification"
    description = "Checks production signing configuration before building a release artifact."

    doLast {
        if (!releaseSigningConfigured) {
            throw GradleException(
                "Build RELEASE dibatalkan: signing belum dikonfigurasi. " +
                    "Isi android/key.properties dengan storeFile, storePassword, " +
                    "keyAlias, dan keyPassword. Jangan menandatangani release dengan debug key."
            )
        }

        if (releaseKeystoreFile?.isFile != true) {
            throw GradleException(
                "Build RELEASE dibatalkan: file keystore pada android/key.properties tidak ditemukan."
            )
        }
    }
}

tasks.configureEach {
    val isReleasePackagingTask =
        name.contains("Release", ignoreCase = true) &&
            (
                name.startsWith("assemble", ignoreCase = true) ||
                    name.startsWith("bundle", ignoreCase = true) ||
                    name.startsWith("package", ignoreCase = true) ||
                    name.startsWith("validateSigning", ignoreCase = true)
                )

    if (isReleasePackagingTask) {
        dependsOn(verifyReleaseSigning)
    }
}

android {
    namespace = "com.musikku.app"

    // Explicit because native security/logger code relies on BuildConfig.DEBUG.
    buildFeatures {
        buildConfig = true
    }

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
            if (releaseSigningConfigured) {
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
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

            // Release harus menggunakan keystore penerbit yang stabil.
            // Pemeriksaan di atas sengaja menggagalkan task release jika keystore belum ada.
            signingConfig = signingConfigs.getByName("release")
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