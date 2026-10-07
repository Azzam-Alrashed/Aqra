pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // LiveKit's audio routing is published only on JitPack; nothing else is taken from there.
        maven("https://jitpack.io") {
            content { includeModule("com.github.davidliu", "audioswitch") }
        }
    }
}

rootProject.name = "Aqra"
include(":app")
