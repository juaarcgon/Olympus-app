import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Carga la configuración de firma de release desde android/key.properties.
// Este archivo NO se versiona (está en .gitignore) y contiene las rutas y
// contraseñas del keystore propio. Si no existe (p. ej. en una máquina de
// desarrollo sin el keystore), el build de release recae en la firma de debug
// para que `flutter run --release` siga funcionando localmente.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.olympus.gym"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identificador único de la aplicación. Debe ser propio (no com.example)
        // para poder publicar y para no colisionar con otras apps.
        applicationId = "com.olympus.gym"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Configuración de firma de release basada en el keystore propio.
        // Solo se crea si key.properties está presente.
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Usa la firma de release si hay keystore propio; en su defecto,
            // recae en la firma de debug (solo para pruebas locales, NUNCA
            // para distribuir la APK a terceros).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Ofuscación y reducción de código/recursos para endurecer la APK
            // y reducir su tamaño. Las reglas de Flutter y los plugins se
            // mantienen con proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
