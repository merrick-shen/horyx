import com.android.build.api.variant.impl.VariantOutputImpl
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 读取正式签名配置（android/key.properties 不入库，见 android/.gitignore）
// 文件缺失时（如 CI 或他人克隆）降级为 debug 签名，保证开发流程不被阻断
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.merrickshen.horyx"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.merrickshen.horyx"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 只保留 arm64 原生库。--target-platform android-arm64 仅裁剪 Flutter 引擎与 Dart
    // 产物，管不住插件自带的 .so（mobile_scanner 的 ML Kit 会为三套 ABI 都打包 barhopper
    // 模型库，多占约 9MB）。注意：AGP 9 中 defaultConfig 的 ndk.abiFilters 已无法过滤
    // 依赖 AAR 携带的 so（实测无效），必须用打包阶段 excludes 按 ABI 目录剔除
    packaging {
        jniLibs {
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86_64/**")
        }
    }

    signingConfigs {
        // 正式签名：仅当 key.properties 存在时创建（内容见 android/key.properties）
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 有正式签名用正式签名，否则回退 debug（本地无 key.properties 的场景）
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

// APK 输出重命名：app-release.apk → Horyx-v{版本号}-{debug|release}.apk
// 版本号自动取自 pubspec.yaml 的 version
// AGP 9 移除了旧 applicationVariants API，改用 Variant API 重命名；
// VariantOutputImpl 为内部实现类，是当前唯一可设置 outputFileName 的途径（官方 gradle-recipes 同款写法）
val appVerName = flutter.versionName
androidComponents {
    onVariants(selector().all()) { variant ->
        variant.outputs.forEach { output ->
            (output as VariantOutputImpl).outputFileName.set(
                "Horyx-v$appVerName-${variant.name}.apk"
            )
        }
    }
}
