/*
 * This file was generated by the Gradle 'init' task.
 *
 * This generated file contains a sample Java application project to get you started.
 * For more details on building Java & JVM projects, please refer to https://docs.gradle.org/8.10.2/userguide/building_java_projects.html in the Gradle documentation.
 * This project uses @Incubating APIs which are subject to change.
 */

plugins {
    // Apply the application plugin to add support for building a CLI application in Java.
    application
    java
}

repositories {
    // Use Maven Central for resolving dependencies.
    mavenCentral()
}

dependencies {
    // This dependency is used by the application.
    implementation(libs.guava)
    // Added dependencies for Aeron Cluster, Agrona, and SLF4J
    implementation("io.aeron:aeron-all:1.46.2")
    implementation("org.agrona:agrona:1.15.0")
    implementation("org.slf4j:slf4j-api:2.0.9")
    implementation("ch.qos.logback:logback-core:1.5.12")
    implementation("ch.qos.logback:logback-classic:1.5.12")
}

// Apply a specific Java toolchain to ease working on different environments.
java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

application {
    // Define the main class for the application.
    mainClass = "org.example.Container"
}

tasks.jar {
    manifest {
        attributes["Main-Class"] = application.mainClass
    }
    
    // Include all dependencies in the JAR
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) })
    
    // Exclude META-INF signatures to avoid conflicts
    exclude("META-INF/*.RSA", "META-INF/*.SF", "META-INF/*.DSA")
    
    // Handle duplicate files
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
}

tasks.test {
    useJUnitPlatform()
}
