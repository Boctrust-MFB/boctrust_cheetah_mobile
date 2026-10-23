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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// dojah_kyc_sdk_flutter 0.1.17 fixes its Java target at 1.8 but otherwise
// inherits Kotlin 21. Align this plugin only; other plugins retain their own
// toolchain settings.
subprojects {
    if (name == "dojah_kyc_sdk_flutter") {
        afterEvaluate {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                compileSdk = 36
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
        }
    }
}

// Smile ID's capture screens (camposer) rebind the camera in a loop on CameraX
// above 1.5.0, which shows as a blinking selfie preview. camera_android_camerax
// pulls 1.6.x, so the whole build is held at Smile's supported version.
// See smileidentity/flutter-v11#223. Remove once Smile ships a fix.
subprojects {
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.camera") {
                useVersion("1.5.0")
                because("Smile ID capture requires CameraX 1.5.0")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
