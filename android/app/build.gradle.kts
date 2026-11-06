plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// 应用标识唯一真源：android/gradle.properties 的单个 property。
val appId = providers.gradleProperty("PUREPACE_APPLICATION_ID").get()

// versionName 每次构建从仓库根 VERSION 读取，不在任何提交文件里写死。
val repoVersion = rootProject.file("../VERSION").readText().trim()

android {
    namespace = appId
    compileSdk = 36

    defaultConfig {
        applicationId = appId
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = repoVersion
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

kotlin {
    jvmToolchain(21)
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.03.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.10.1")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation(composeBom)
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.17")
    testImplementation("androidx.compose.ui:ui-test-junit4")
}
