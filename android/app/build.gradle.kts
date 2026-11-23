plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.intono"   // placeholder app id until Phase 5 (ADR 0009 answers)
    compileSdk = 35
    ndkVersion = "30.0.16248370"

    defaultConfig {
        applicationId = "com.example.intono"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0-phase2"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            // x86_64 is for the CI emulator only; the phone is arm64-v8a.
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
        externalNativeBuild {
            cmake {
                // Oboe's Prefab package ships only libc++_shared builds, so the shim uses the shared STL (ADR 0009 Amendment 1).
                arguments += listOf("-DANDROID_STL=c++_shared", "-DANDROID_ARM_NEON=ON", "-DCMAKE_BUILD_TYPE=Release")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../shim/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        prefab = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("com.google.oboe:oboe:1.9.3")

    testImplementation("junit:junit:4.13.2")

    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
