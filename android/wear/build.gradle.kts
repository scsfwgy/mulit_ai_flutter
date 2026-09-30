import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
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
