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
// 旧插件（如 file_picker 8.x）自声明 compileSdk 低于 Flutter 3.44 默认的 36，
// 会触发 AAR metadata 校验失败；此处统一抬升到 36。
// 必须在 evaluationDependsOn 触发 :app 求值之前注册 afterEvaluate。
subprojects {
    val bumpSdk: (Project) -> Unit = {
        val androidExt = it.extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            val current = androidExt.compileSdkVersion
            if (current != null && current.substringAfter("android-").toIntOrNull()?.let { v -> v < 36 } == true) {
                androidExt.compileSdkVersion = "android-36"
            }
        }
    }
    if (state.executed) bumpSdk(project) else afterEvaluate { bumpSdk(project) }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
