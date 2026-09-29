import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val releaseProperties = Properties().apply {
    val config = rootProject.file("key.properties")
    if (config.isFile) config.inputStream().use(::load)
}
val releaseCredentials = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !releaseProperties.getProperty(it).isNullOrBlank() }
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (releaseRequested && !releaseCredentials) {
    error("Release signing requires android/key.properties (see android/key.properties.example)")
}
val watchBuildCode = providers.gradleProperty("watchVersionCode").orNull?.toIntOrNull() ?: 1000001
val watchBuildName = providers.gradleProperty("watchVersionName").orNull ?: "1.0.0"

android {
    namespace = "com.maxhall.ailink.wear"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.maxhall.ailink"
        minSdk = 30
        targetSdk = 36
        versionCode = watchBuildCode
        versionName = watchBuildName
    }

    signingConfigs {
        if (releaseCredentials) create("release") {
            storeFile = rootProject.file(releaseProperties.getProperty("storeFile"))
            storePassword = releaseProperties.getProperty("storePassword")
            keyAlias = releaseProperties.getProperty("keyAlias")
            keyPassword = releaseProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            if (releaseCredentials) signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    implementation("androidx.wear:wear-remote-interactions:1.2.0")
    testImplementation("junit:junit:4.13.2")
}
