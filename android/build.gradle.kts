group = "com.adfacten.ads.flutter"
version = "1.0.1"

// Native Adfacten SDK version this plugin is built against.
val adfactenSdkVersion = "1.0.2"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

// The native SDK is served from Adfacten's own Maven repository. Add it to every project of the app
// build so the app module can resolve it without any setup. Builds that declare repositories only in
// settings.gradle (RepositoriesMode.FAIL_ON_PROJECT_REPOS or PREFER_SETTINGS) must add it there.
val adfactenRepo = "https://cdn.adfacten.com/maven/"
rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri(adfactenRepo)
            content { includeGroup("com.adfacten") }
        }
    }
}

plugins {
    id("com.android.library")
}

fun flag(name: String, default: Boolean): Boolean =
    providers.gradleProperty(name).orNull?.trim()?.toBooleanStrictOrNull() ?: default

android {
    namespace = "com.adfacten.ads.flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.adfacten:ads:$adfactenSdkVersion")
    // VAST video for interstitial and rewarded ads (Media3 ExoPlayer). On by default; set
    // adfacten.video=false in android/gradle.properties to leave it out.
    if (flag("adfacten.video", true)) {
        implementation("com.adfacten:ads-video:$adfactenSdkVersion")
    }
    // Google advertising ID + App Set ID. Adds the AD_ID permission, so it is opt-in:
    // adfacten.gaid=true in android/gradle.properties.
    if (flag("adfacten.gaid", false)) {
        implementation("com.adfacten:ads-gaid:$adfactenSdkVersion")
    }
}
