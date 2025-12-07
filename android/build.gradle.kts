plugins {
    // 版本依你的專案為準，這是常見組合
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    id("dev.flutter.flutter-gradle-plugin") apply false
    // 關鍵：先在頂層宣告 google-services，但不要套用
    id("com.google.gms.google-services")
}

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
