package com.music.bitchord

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppIconVariantsTest {
    private val variantIds = listOf(
        "liquid_glass",
        "liquid_glass_dark",
        "liquid_glass_clear",
        "neon_silver",
        "neon_cyan",
        "neon_violet",
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
        assertTrue("Missing monochrome adaptive launcher resource", File(resourcesDir(), "mipmap-anydpi/ic_monochrome.xml").isFile)
    }


    @Test
    fun allLauncherStylesUseTheSameFiveBarEqualizer() {
        val resources = resourcesDir()
        val barPaths = listOf(
            "M24,28 V78",
            "M39,42 V78",
            "M54,33 V78",
            "M69,47 V78",
            "M84,27 V78",
        )
        val launcherAssets = listOf(
            "drawable/ic_variant_default.xml",
            "drawable/ic_variant_monochrome.xml",
        ) + variantIds.map { "drawable/ic_variant_$it.xml" } + listOf(
            "drawable/ic_launcher_foreground.xml",
            "drawable/ic_musikku_launcher.xml",
            "drawable/ic_musikku_launcher_round.xml",
            "drawable/ic_musikku_monochrome.xml",
        )

        launcherAssets.forEach { path ->
            val file = File(resources, path)
            assertTrue("Missing equalizer artwork: $path", file.isFile)
            val artwork = file.readText()
            barPaths.forEach { bar ->
                assertTrue("$path must use the shared bar path $bar", artwork.contains(bar))
            }
            assertFalse("$path must not keep the old M monogram", artwork.contains("M25,78 V35"))
        }

        val manifest = File(appRoot, "src/main/AndroidManifest.xml").readText()
        val expectedAliases = listOf(
            "LauncherDefault",
            "LauncherMonochrome",
            "LauncherGlassLight",
            "LauncherGlassDark",
            "LauncherGlassClear",
            "LauncherNeonSilver",
            "LauncherNeonCyan",
            "LauncherNeonViolet",
        )
        expectedAliases.forEach { alias ->
            assertTrue("Missing launcher alias $alias", manifest.contains("android:name=\".$alias\""))
        }
        assertEquals(
            "Settings should expose exactly the eight launcher styles",
            8,
            Regex("android:name=\\\"\\.Launcher").findAll(manifest).count(),
        )
        assertFalse("Samsung-specific duplicate aliases should be removed", manifest.contains("LauncherSamsung"))
        assertFalse("Pixel-specific duplicate aliases should be removed", manifest.contains("LauncherPixel"))
    }

    @Test
    fun appIconPreviewsReserveSpaceAndKeepLabelsBelowTheArtwork() {
        val settings = File(
            appRoot,
            "src/main/java/com/music/bitchord/ui/screens/SettingsSheet.kt",
        ).readText()

        assertFalse("Icon previews must not paint outside their measured layout", settings.contains(".scale(1.5f)"))
        assertTrue("Every icon preview needs a measured square slot", settings.contains("Modifier.size(68.dp)"))
        assertTrue("Icon labels need a stable two-line area", settings.contains("minLines = 2"))
    }


    @Test
    fun replayAndProductLogosUseTheSameSolidMusikKuMark() {
        val projectRoot = appRoot.parentFile ?: appRoot
        val sharedLogo = File(
            projectRoot,
            "sharedUi/src/commonMain/composeResources/drawable/ic_logo.xml",
        ).readText()
        val appLogo = File(resourcesDir(), "drawable/ic_logo.xml").readText()
        val wearLogo = File(
            projectRoot,
            "wearos/src/main/res/drawable/ic_logo.xml",
        ).readText()
        val webLogo = File(projectRoot, "web/app/src/assets/logo-mark.svg").readText()
        val transparentLogo = File(appRoot, "src/main/assets/LogoTransparent.svg").readText()
        val svgLogo = File(appRoot, "src/main/assets/Logo.svg").readText()
        val solidMark = "M25,78 V35 C25,23 39,18 47,28 L54,37 L62,28 C70,18 84,23 84,35 V78 H70 V42 L54,58 L38,42 V78 Z"

        listOf(sharedLogo, appLogo, wearLogo).forEach { logo ->
            assertTrue("Android and Replay marks must be solid", logo.contains(solidMark))
            assertFalse("In-app logos must not use an outlined M", logo.contains("android:strokeWidth"))
        }
        assertTrue("Web mark must be filled", webLogo.contains("fill=") && webLogo.contains("currentColor"))
        assertTrue("Transparent mark must be filled", transparentLogo.contains("url(#mark)") && transparentLogo.contains("M25 78V35"))
        assertTrue("Full SVG mark must be filled", svgLogo.contains("url(#mark)") && svgLogo.contains("M120 369V166"))
        assertFalse("Web mark must not keep the previous M outline", webLogo.contains("stroke-width") && webLogo.contains("7.5"))
        assertFalse("Transparent mark must not keep the previous M outline", transparentLogo.contains("stroke-width") && transparentLogo.contains("7.5"))
    }

    private fun resourcesDir() = File(appRoot, "src/main/res")
}
