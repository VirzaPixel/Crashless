plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    kotlin("android") version "2.2.20"
}

android {
    namespace = "com.example.crashless_mobile"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    
    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.crashless_mobile"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        
        multiDexEnabled = true
        
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a"))
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/ASL2.0",
                "META-INF/*.kotlin_module"
            )
        }
    }
    
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

flutter {
    source = "../.."
}

// Custom task to copy APK to Flutter expected location
afterEvaluate {
    tasks.register<Copy>("copyApkToFlutterOutput") {
        description = "Copy APK from Gradle output to Flutter expected location"
        group = "build"
        
        from("$buildDir/outputs/flutter-apk")
        into("$rootDir/../build/app/outputs/flutter-apk")
        include("*.apk")
        
        mustRunAfter("assembleRelease")
    }

    // Auto-run copy task after assembleRelease
    tasks.named("assembleRelease").configure {
        finalizedBy("copyApkToFlutterOutput")
    }
}
