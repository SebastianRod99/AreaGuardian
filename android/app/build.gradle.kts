import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningPropertiesFile.exists()) {
        releaseSigningPropertiesFile.inputStream().use { load(it) }
    }
}

dependencies {
    // Import the Firebase BoM (Bill of Materials)
    implementation(platform("com.google.firebase:firebase-bom:33.9.0"))

    // Productos de Firebase que usará AreaGuardian:
    implementation("com.google.firebase:firebase-analytics")

    // 🔔 Esenciales para la red de alertas a puestos cercanos:
    implementation("com.google.firebase:firebase-messaging") // Para notificaciones push (FCM)
    implementation("com.google.firebase:firebase-firestore") // Para almacenar y buscar puestos/alertas cercanas
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

android {
    namespace = "com.areaguardian.app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.areaguardian.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            releaseSigningProperties.getProperty("storeFile")
                ?.takeIf(String::isNotBlank)
                ?.let { storeFile = rootProject.file(it) }
            storePassword = releaseSigningProperties.getProperty("storePassword")
            keyAlias = releaseSigningProperties.getProperty("keyAlias")
            keyPassword = releaseSigningProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    doLast {
        val requiredProperties = listOf(
            "storeFile",
            "storePassword",
            "keyAlias",
            "keyPassword",
        )
        val missingProperties = requiredProperties.filter {
            releaseSigningProperties.getProperty(it).isNullOrBlank()
        }
        check(missingProperties.isEmpty()) {
            "Release signing is not configured. Add all required values to android/key.properties."
        }
        val storeFilePath = releaseSigningProperties.getProperty("storeFile")
        check(!storeFilePath.isNullOrBlank() && rootProject.file(storeFilePath).isFile) {
            "The release keystore configured in android/key.properties was not found."
        }
    }
}

tasks.configureEach {
    if (name == "assembleRelease" || name == "bundleRelease") {
        dependsOn(validateReleaseSigning)
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
