import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// ---- Which Firebase project a build talks to (README.md, "Builds") ----
//
// Debug builds talk to the local emulators unless production is asked for; a release always talks to production.
// The google-services plugin works per project, not per variant: when it's applied, every variant starts Firebase as
// the real project before the app could set it up as the emulators' demo project. So one Gradle run builds either
// emulator builds or production ones, and the release is always its own run.
val emulatorFlag = project.findProperty("useFirebaseEmulator")?.toString()
val emulatorAsked = emulatorFlag != null && (emulatorFlag.isEmpty() || emulatorFlag.toBoolean())
val productionAsked = project.hasProperty("aqra.production") || (emulatorFlag != null && !emulatorAsked)
val debugUsesEmulator = !productionAsked
// The Firebase config isn't in git (see README.md). Without it the app runs with accounts and backup off.
val hasFirebaseConfig = file("google-services.json").exists()
// A CI runner has no config: its release is a compile-and-shrink check and says so with this property or variable.
val ciRelease = project.hasProperty("aqra.ciRelease") || System.getenv("AQRA_CI_RELEASE") == "1"
val requestedTasks = gradle.startParameter.taskNames.map { it.substringAfterLast(':') }
val buildsRelease = requestedTasks.any { it.contains("Release") || it in setOf("assemble", "build", "bundle", "install") }
val buildsDebug = requestedTasks.any { it.contains("Debug") || it in setOf("assemble", "build", "bundle", "install") }
if (buildsRelease && buildsDebug && debugUsesEmulator) {
    throw GradleException("Build the release in its own Gradle run: a debug build for the emulators and a release can't share one (README.md, \"Builds\").")
}
if (hasFirebaseConfig && (productionAsked || buildsRelease)) {
    apply(plugin = libs.plugins.google.services.get().pluginId)
}

// ---- Signing (README.md, "Signing the release") ----
// The Play upload key: apps/android/keystore.properties (gitignored; keystore.properties.example lists its keys). Without
// it a release is built unsigned, which Play refuses but a compile check doesn't need.
val keystoreFile = rootProject.file("keystore.properties")
val keystore = Properties().apply { if (keystoreFile.exists()) keystoreFile.inputStream().use(::load) }

android {
    namespace = "com.azzamalrashed.aqra"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.azzamalrashed.aqra"
        minSdk = 26
        targetSdk = 36
        // Each upload to Play needs a higher code: -Paqra.versionCode=N (and -Paqra.versionName=x.y.z) on the release run.
        versionCode = project.findProperty("aqra.versionCode")?.toString()?.toInt() ?: 2
        versionName = project.findProperty("aqra.versionName")?.toString() ?: "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Debug builds talk only to the local emulators (see backend/README.md) unless built with -Paqra.production.
        buildConfigField("boolean", "USE_FIREBASE_EMULATOR", debugUsesEmulator.toString())
        // Whether the Firebase config is bundled: never in an emulator build, whose plugin stays off.
        buildConfigField("boolean", "HAS_FIREBASE_CONFIG", (hasFirebaseConfig && !debugUsesEmulator).toString())
    }

    signingConfigs {
        if (keystoreFile.exists()) {
            create("release") {
                storeFile = rootProject.file(keystore.getProperty("storeFile"))
                storePassword = keystore.getProperty("storePassword")
                keyAlias = keystore.getProperty("keyAlias")
                keyPassword = keystore.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("boolean", "USE_FIREBASE_EMULATOR", "false")
            buildConfigField("boolean", "HAS_FIREBASE_CONFIG", hasFirebaseConfig.toString())
            signingConfig = signingConfigs.findByName("release")
        }
    }

    // Play builds each device's APK from the bundle: its own ABI's native code (ONNX Runtime and LiveKit are most of
    // the app), its screen density's drawables and its languages. The universal APK of assembleRelease has them all.
    bundle {
        abi { enableSplit = true }
        density { enableSplit = true }
        language { enableSplit = true }
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

// A release that would ship wrong stops before it compiles: with accounts off (no Firebase config), or pointed at the
// emulators. The check runs with the release's own tasks only, so debug builds and tests never see it.
val checkReleaseConfig = tasks.register("checkReleaseConfig") {
    val emulatorAsked = emulatorAsked
    val hasFirebaseConfig = hasFirebaseConfig
    val ciRelease = ciRelease
    val signed = keystoreFile.exists()
    doLast {
        if (emulatorAsked) {
            throw GradleException("A release never talks to the emulators: leave out -PuseFirebaseEmulator and build the release in its own Gradle run.")
        }
        if (!hasFirebaseConfig && !ciRelease) {
            throw GradleException("A release needs app/google-services.json, or it ships with accounts off. On a CI runner, which has none, pass -Paqra.ciRelease (or set AQRA_CI_RELEASE=1) for a compile check.")
        }
        if (!signed) logger.warn("No apps/android/keystore.properties: this release is unsigned (README.md, \"Signing the release\").")
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach { dependsOn(checkReleaseConfig) }
tasks.matching { it.name == "assembleRelease" || it.name == "bundleRelease" }.configureEach { dependsOn(checkReleaseConfig) }

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
    // Listening to a revision: runs the Quran-trained Whisper model on the device (recitation/).
    implementation(libs.onnxruntime.android)

    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.sqlite.jdbc)
}
