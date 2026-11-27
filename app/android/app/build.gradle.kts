plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.intono"   // placeholder app id until Phase 5 (ADR 0009 answers)
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "30.0.16248370"       // the shim is built with the same NDK as the harness

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.intono"
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // x86_64 is for the CI emulator only; the phone is arm64-v8a.
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
        externalNativeBuild {
            cmake {
                // Oboe's Prefab package ships only libc++_shared builds, so the shim uses the shared STL (ADR 0009 Amendment 1).
                arguments += listOf("-DANDROID_STL=c++_shared", "-DANDROID_ARM_NEON=ON", "-DCMAKE_BUILD_TYPE=Release")
                // The bench APK also carries libintono_bench_noguard.so (denormal guard OFF) for the on-device comparison, information
                // only (ADR 0009 answer 4). Set INTONO_BENCH=1 in the environment of that build; no other build contains it.
                if (System.getenv("INTONO_BENCH") == "1") arguments += "-DINTONO_BENCH_NOGUARD=ON"
            }
        }
    }

    // The same native shim and the same Kotlin glue as the harness app: one source of truth (ADR 0009 decision 1).
    externalNativeBuild {
        cmake {
            path = file("../../../android/shim/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    sourceSets.getByName("main").java.srcDir("../../../android/app/src/main/kotlin")

    buildFeatures {
        prefab = true
    }
}

dependencies {
    implementation("com.google.oboe:oboe:1.9.3")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
