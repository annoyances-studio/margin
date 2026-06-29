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

    // Some plugins pin an older compileSdk than their (newer) AndroidX
    // dependencies require — notably desktop_drop, which is desktop-only for us
    // but still builds on Android. Force every Android library subproject to
    // compile against the app's SDK so the AAR-metadata check passes. Registered
    // here, before the evaluationDependsOn block below forces evaluation.
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.LibraryExtension>()
            ?.compileSdk = 36
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
