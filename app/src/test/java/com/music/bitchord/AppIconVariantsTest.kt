package com.music.bitchord

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AppIconVariantsTest {
    private val variantIds = listOf(
        "liquid_glass",
        "liquid_glass_dark",
        "liquid_glass_clear",
        "liquid_glass_clear_dark",
        "samsung_glass",
        "samsung_glass_dark",
        "samsung_glass_clear",
        "samsung_glass_clear_dark",
        "pixel_glass",
        "pixel_glass_dark",
        "pixel_glass_clear",
        "pixel_glass_clear_dark",
        "neon_silver",
        "neon_cyan",
        "neon_violet",
        "samsung_neon_silver",
        "samsung_neon_cyan",
        "samsung_neon_violet",
        "pixel_neon_silver",
        "pixel_neon_cyan",
        "pixel_neon_violet",
    )

    private val appRoot: File
        get() {
            val workingDirectory = File(".").canonicalFile
            val projectRoot = if (File(workingDirectory, "app").isDirectory) {
                workingDirectory
            } else {
                workingDirectory.parentFile ?: workingDirectory
            }
            return File(projectRoot, "app")
        }

    @Test
    fun everyLauncherStyleHasItsOwnAdaptiveArtworkAndPreview() {
        val resources = File(appRoot, "src/main/res")
        val appIconSource = File(
            appRoot,
            "src/main/java/com/music/bitchord/AppIcon.kt",
        ).readText()

        val artworkContents = mutableListOf<String>()
        val foregroundResources = variantIds.map { id ->
            val drawable = File(resources, "drawable/ic_variant_$id.xml")
            val adaptiveIcon = File(resources, "mipmap-anydpi/ic_$id.xml")

            assertTrue(drawable.isFile, "Missing artwork for $id")
            assertTrue(adaptiveIcon.isFile, "Missing adaptive icon for $id")

            val artwork = drawable.readText()
            val adaptiveXml = adaptiveIcon.readText()
            val expectedForeground = "@drawable/ic_variant_$id"
            assertTrue(
                adaptiveXml.contains(expectedForeground),
                "$id does not reference its own foreground artwork",
            )
            artworkContents += artwork
            assertTrue(
                appIconSource.contains("R.drawable.ic_variant_$id"),
                "$id preview does not use its own artwork",
            )
            expectedForeground
        }

        assertEquals(
            variantIds.size,
            foregroundResources.toSet().size,
            "Launcher variants must not share the same foreground resource",
        )
        assertEquals(
            variantIds.size,
            artworkContents.toSet().size,
            "Launcher variants must not reuse identical artwork files",
        )
    }

    @Test
    fun defaultLauncherUsesAndroidAdaptiveIconResources() {
        val manifest = File(appRoot, "src/main/AndroidManifest.xml").readText()

        assertTrue(manifest.contains("android:icon=\"@mipmap/ic_launcher\""))
        assertTrue(manifest.contains("android:roundIcon=\"@mipmap/ic_launcher_round\""))
        assertTrue(File(resourcesDir(), "mipmap-anydpi-v26/ic_launcher.xml").isFile)
        assertTrue(File(resourcesDir(), "mipmap-anydpi-v26/ic_launcher_round.xml").isFile)
    }

    private fun resourcesDir() = File(appRoot, "src/main/res")
}
