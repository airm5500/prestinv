allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Certains plugins (ex. printing 5.13) compilent avec un SDK Android trop ancien
// (« resource android:attr/lStar not found » au build release) : on leur impose
// le SDK de compilation de Flutter (35), sans changer minSdk ni le code des plugins.
subprojects {
    val forcerCompileSdk: Project.() -> Unit = {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { ext ->
            if ((ext.compileSdk ?: 0) < 35) ext.compileSdk = 35
        }
    }
    if (state.executed) forcerCompileSdk() else afterEvaluate { forcerCompileSdk() }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
