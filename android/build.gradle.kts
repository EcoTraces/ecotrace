allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // file_picker 11 assumes every AGP 9 project uses built-in Kotlin and
    // otherwise skips compiling its Kotlin sources. Firebase still requires
    // the temporary external-Kotlin compatibility mode, so apply KGP only to
    // file_picker when its Android library plugin becomes available.
    if (project.name == "file_picker") {
        pluginManager.withPlugin("com.android.library") {
            if (!pluginManager.hasPlugin("org.jetbrains.kotlin.android")) {
                pluginManager.apply("org.jetbrains.kotlin.android")
            }
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }

    // FlutterFire's legacy Groovy build files may request AGP 8.3 directly.
    // Keep every Android subproject on the AGP version selected in settings.
    buildscript.configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (
                requested.group == "com.android.tools.build" &&
                requested.name == "gradle"
            ) {
                useVersion("9.0.1")
                because("The application and Flutter plugins share one AGP runtime.")
            }
            if (
                requested.group == "org.jetbrains.kotlin" &&
                requested.name == "kotlin-reflect" &&
                requested.version == "2.2.10"
            ) {
                useVersion("2.3.0")
                because("Use the compatible Kotlin reflection artifact cached with this toolchain.")
            }
            if (
                requested.group == "org.jetbrains.kotlin" &&
                requested.name == "kotlin-gradle-plugin" &&
                requested.version == "2.4.10"
            ) {
                useVersion("2.3.20")
                because("Use the Kotlin Android plugin selected by this application.")
            }
        }
    }

    afterEvaluate {
        extensions
            .findByType(com.android.build.api.dsl.LibraryExtension::class.java)
            ?.apply {
                compileSdk = 36
                compileSdkMinor = 1
                ndkVersion = "30.0.15729638"
                if (project.name == "jni") {
                    externalNativeBuild.cmake.version = "4.1.2"
                }
            }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
