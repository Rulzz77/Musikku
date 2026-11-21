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

            assertTrue("Missing artwork for $id", drawable.isFile)
            assertTrue("Missing adaptive icon for $id", adaptiveIcon.isFile)

            val artwork = drawable.readText()
            val adaptiveXml = adaptiveIcon.readText()
            val expectedForeground = "@drawable/ic_variant_$id"
            assertTrue("$id does not reference its own foreground artwork", adaptiveXml.contains(expectedForeground))
            artworkContents += artwork
            assertTrue("$id preview does not use its own artwork", appIconSource.contains("R.drawable.ic_variant_$id"))
            expectedForeground
        }

        assertEquals("Launcher variants must not share the same foreground resource", variantIds.size, foregroundResources.toSet().size)
        assertEquals("Launcher variants must not reuse identical artwork files", variantIds.size, artworkContents.toSet().size)
    }

    @Test
    fun defaultLauncherUsesAndroidAdaptiveIconResources() {
        val manifest = File(appRoot, "src/main/AndroidManifest.xml").readText()

        assertTrue("Default launcher must use the adaptive icon", manifest.contains("android:icon=\"@mipmap/ic_launcher\""))
        assertTrue("Round launcher must use the adaptive icon", manifest.contains("android:roundIcon=\"@mipmap/ic_launcher_round\""))
        assertTrue("Missing adaptive launcher resource", File(resourcesDir(), "mipmap-anydpi-v26/ic_launcher.xml").isFile)
        assertTrue("Missing round adaptive launcher resource", File(resourcesDir(), "mipmap-anydpi-v26/ic_launcher_round.xml").isFile)
    }

    private fun resourcesDir() = File(appRoot, "src/main/res")
}
