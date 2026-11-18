pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "RideTracker"

// Pure logic, the Kotlin twin of ios/Packages/RideKit. Checked against ../spec/fixtures.
include(":ridekit")

// The app (Compose). Rules: ../CLAUDE.md and ../PLAN-ANDROID.md.
include(":app")
