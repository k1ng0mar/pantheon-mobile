pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Pinned to the Flutter 3.47 floor, not the latest template AGP 9: the
    // cargokit build in super_native_extensions (via syntax_highlight ->
    // super_clipboard) still uses Project.exec() and the old variant API,
    // both removed in Gradle 9 / AGP 9. 8.11.1 builds it cleanly.
    id("com.android.application") version "8.11.1" apply false
    // Flutter 3.47 needs Kotlin >= 2.2.20; 2.2.20 also keeps the stdlib
    // metadata at 2.2.x so AGP 8.11.1 reads it (2.4.0 stdlib does not).
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
