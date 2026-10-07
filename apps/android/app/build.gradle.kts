import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// The Firebase config isn't in git (see README.md). Without it the app still runs, with accounts and backup off.
val hasFirebaseConfig = file("google-services.json").exists()
if (hasFirebaseConfig) {
    apply(plugin = libs.plugins.google.services.get().pluginId)
}

android {
    namespace = "com.azzamalrashed.aqra"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.azzamalrashed.aqra"
        minSdk = 26
        targetSdk = 36
        versionCode = 2
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Debug builds made with -PuseFirebaseEmulator talk only to the local emulators (see backend/README.md).
        buildConfigField("boolean", "USE_FIREBASE_EMULATOR", (project.findProperty("useFirebaseEmulator") != null).toString())
        buildConfigField("boolean", "HAS_FIREBASE_CONFIG", hasFirebaseConfig.toString())
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("boolean", "USE_FIREBASE_EMULATOR", "false")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    androidResources {
        // The page fonts are already compressed, and the layout databases are copied out as they are.
        noCompress += listOf("woff2", "db", "ttf")
        generateLocaleConfig = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

/**
 * Bundles the shared Quran data (shared/quran) as the app's "quran" assets, exactly as it is in the repository.
 * The 604 page fonts aren't in git: restore them with scripts/fetch-mushaf-fonts.sh before building.
 */
abstract class QuranAssets : DefaultTask() {
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val source: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @get:Inject
    abstract val files: FileSystemOperations

    @TaskAction
    fun copy() {
        val fonts = source.get().dir("qcf4").asFile.listFiles { file -> file.extension == "woff2" }?.size ?: 0
        if (fonts != 604) {
            logger.warn("Only $fonts of 604 Mushaf page fonts are in shared/quran/qcf4. Run scripts/fetch-mushaf-fonts.sh, then rebuild.")
        }
        files.sync {
            from(source) {
                exclude("README.md")
                into("quran")
            }
            into(outputDir)
        }
    }
}

val quranAssets = tasks.register<QuranAssets>("quranAssets") {
    source.set(rootProject.layout.projectDirectory.dir("../../shared/quran"))
    outputDir.set(layout.buildDirectory.dir("generated/quranAssets"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(quranAssets, QuranAssets::outputDir)
    }
}

// The unit tests read the same shared data, straight from the repository.
tasks.withType<Test>().configureEach {
    systemProperty("aqra.quranDir", rootProject.layout.projectDirectory.dir("../../shared/quran").asFile.absolutePath)
    // Written by tools/coretext-reference.swift on a Mac; the comparison with CoreText is skipped without it.
    systemProperty("aqra.coretextDir", rootProject.layout.buildDirectory.dir("coretext").get().asFile.absolutePath)
    maxHeapSize = "2g"
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.brotli.dec)

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.firestore)
    implementation(libs.firebase.storage)
    implementation(libs.firebase.functions)
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services)
    implementation(libs.googleid)
    implementation(libs.zxing.core)
    implementation(libs.code.scanner)
    implementation(libs.livekit.android)

    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.sqlite.jdbc)
}
