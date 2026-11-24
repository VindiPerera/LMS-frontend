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
// file_picker and screen_protector skip applying the Kotlin plugin on AGP 9+,
// expecting AGP's built-in Kotlin to compile their sources. This project keeps
// built-in Kotlin off (android.builtInKotlin=false in gradle.properties) because
// other plugins still apply KGP themselves, so without this their Kotlin classes
// never get compiled ("cannot find symbol FilePickerPlugin/ScreenProtectorPlugin").
val pluginsNeedingKotlin = setOf("file_picker", "screen_protector")
subprojects {
    if (project.name in pluginsNeedingKotlin) {
        project.plugins.withId("com.android.library") {
            project.pluginManager.apply("org.jetbrains.kotlin.android")
        }
        // Match the plugins' Java target (17); otherwise Kotlin defaults to the
        // build JDK's version (21) and Gradle rejects the mismatch.
        project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
