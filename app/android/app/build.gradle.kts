import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key, out of the repository. `key.properties` and the keystore are
// both gitignored: losing them is recoverable through Play App Signing, but
// only by asking Google to reset the upload key, so they are worth backing up.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.sheyaln.aac"
    // 37, not `flutter.compileSdkVersion`, which is 36 in Flutter 3.47.
    // `flutter_secure_storage` publishes AAR metadata requiring 37, and the
    // build fails at `checkReleaseAarMetadata` rather than anywhere that names
    // the plugin. Compiling against a newer API is not the same as targeting
    // it: `targetSdk` and `minSdk` are untouched, so which devices can install
    // this and which runtime behaviors it opts into are both unchanged.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sheyaln.aac"
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

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")
                ?.let { rootProject.file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // Falls back to debug signing when there is no key.properties, so a
            // checkout without the key still builds and runs. Play refuses a
            // debug signed upload, which is the failure anybody without the key
            // should get: a build to try, not a build to publish.
            signingConfig = if (keystoreProperties.isEmpty) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
        }
    }
}

// Refuses a release build with nowhere to send a crash report, on a machine
// marked as one whose builds must be able to. The iOS side of this is a build
// phase in Runner.xcodeproj; this is the same check on the same terms, so that
// neither platform is the way around it.
//
// Silent without the marker, which is what keeps the project buildable by a
// fork, a contributor, or anyone from source — they get an app with no
// reporting and a screen that says so, and are never asked for a credential
// they should not have.
//
// Release only, for the reason the iOS phase gives: a guard people turn off
// guards nothing.
tasks.matching {
    it.name.startsWith("assembleRelease") || it.name.startsWith("bundleRelease")
}.configureEach {
    // Read at configuration time. `--dart-define` reaches Gradle as a project
    // property rather than as an environment variable, and it is the one that
    // actually decides what is compiled in — the same string the iOS phase
    // reads out of DART_DEFINES.
    val dartDefines = project.findProperty("dart-defines")?.toString() ?: ""
    val fromEnvironment = listOf(
        "WORDBRIDGE_INTAKE_URL" to (System.getenv("WORDBRIDGE_INTAKE_URL") ?: ""),
        "WORDBRIDGE_INTAKE_TOKEN" to
            (System.getenv("WORDBRIDGE_INTAKE_TOKEN") ?: ""),
    )
    val check = rootProject.file("../../tools/require-intake.sh")

    doFirst {
        if (!check.exists()) return@doFirst

        val process = ProcessBuilder("/bin/sh", check.absolutePath)
            .redirectErrorStream(true)
            .also { builder ->
                builder.environment()["DART_DEFINES"] = dartDefines
                fromEnvironment.forEach { (key, value) ->
                    builder.environment()[key] = value
                }
            }
            .start()

        val said = process.inputStream.bufferedReader().readText()
        if (process.waitFor() != 0) {
            throw GradleException(
                said.ifBlank { "This build has nowhere to send crash reports." },
            )
        }
    }
}
