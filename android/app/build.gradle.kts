import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProfile = System.getenv("AI_LINK_SIGNING_PROFILE") ?: "release"
require(signingProfile == "release" || signingProfile == "test") {
    "AI_LINK_SIGNING_PROFILE must be release or test"
}
val signingConfigFile = if (signingProfile == "test") "key.test.properties" else "key.properties"
val releaseProperties = Properties().apply {
    val config = rootProject.file(signingConfigFile)
    if (config.isFile) config.inputStream().use(::load)
}
val releaseCredentials = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !releaseProperties.getProperty(it).isNullOrBlank() }
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (releaseRequested && !releaseCredentials) {
    error("$signingProfile signing requires android/$signingConfigFile (see its .example file)")
}

// Development and distributed test builds share a certificate so they can
// update each other and communicate across phone and watch installations.
val testProperties = Properties().apply {
    val config = rootProject.file("key.test.properties")
    if (config.isFile) config.inputStream().use(::load)
}
val testCredentials = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !testProperties.getProperty(it).isNullOrBlank() }
if (gradle.startParameter.taskNames.any { it.contains("Debug", ignoreCase = true) } && !testCredentials) {
    error("Debug signing requires android/key.test.properties (see its .example file)")
}

android {
    namespace = "com.maxhall.ailink"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.maxhall.ailink"
        manifestPlaceholders["appLabel"] = "AI Link"
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
        if (testCredentials) create("test") {
            storeFile = rootProject.file(testProperties.getProperty("storeFile"))
            storePassword = testProperties.getProperty("storePassword")
            keyAlias = testProperties.getProperty("keyAlias")
            keyPassword = testProperties.getProperty("keyPassword")
        }
        if (releaseCredentials) create("release") {
            storeFile = rootProject.file(releaseProperties.getProperty("storeFile"))
            storePassword = releaseProperties.getProperty("storePassword")
            keyAlias = releaseProperties.getProperty("keyAlias")
            keyPassword = releaseProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "AI Link Debug"
            if (testCredentials) signingConfig = signingConfigs.getByName("test")
        }
        release {
            if (signingProfile == "test") {
                applicationIdSuffix = ".debug"
                manifestPlaceholders["appLabel"] = "AI Link Debug"
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (releaseCredentials) signingConfig = signingConfigs.getByName("release")
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

dependencies {
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    implementation("androidx.wear:wear-remote-interactions:1.2.0")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
}
