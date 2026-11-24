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
            "M30,39 V74",
            "M42,48 V74",
            "M54,30 V74",
            "M66,43 V74",
            "M78,35 V74",
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
            assertTrue("$path must keep the smaller safe-area stroke", artwork.contains("android:strokeWidth=\"5.5\""))
            assertFalse("$path must not keep the old M monogram or music-note tail", artwork.contains("M25,78 V35") || artwork.contains("M45,63 V80"))
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
        assertTrue("Artwork should sit smaller inside its preview slot", settings.contains("Modifier.size(64.dp)"))
        assertTrue("Icon labels need a stable two-line area", settings.contains("minLines = 2"))
    }


    @Test
    fun everyProductSurfaceUsesTheSameEqualizerBrandMark() {
        val projectRoot = appRoot.parentFile ?: appRoot
        val sharedLogo = File(
            projectRoot,
            "sharedUi/src/commonMain/composeResources/drawable/ic_logo.xml",
        ).readText()
        val appLogo = File(resourcesDir(), "drawable/ic_logo.xml").readText()
        val notificationLogo = File(resourcesDir(), "drawable/ic_notification_logo.xml").readText()
        val wearLogo = File(
            projectRoot,
            "wearos/src/main/res/drawable/ic_logo.xml",
        ).readText()
        val wearLauncher = File(
            projectRoot,
            "wearos/src/main/res/drawable/ic_launcher_foreground.xml",
        ).readText()
        val wearMonochrome = File(
            projectRoot,
            "wearos/src/main/res/drawable/ic_musikku_monochrome.xml",
        ).readText()
        val xmlBars = listOf(
            "M30,39 V74",
            "M42,48 V74",
            "M54,30 V74",
            "M66,43 V74",
            "M78,35 V74",
        )
        listOf(sharedLogo, appLogo, notificationLogo, wearLogo, wearLauncher, wearMonochrome).forEach { logo ->
            xmlBars.forEach { bar ->
                assertTrue("Android/Wear OS logo must use $bar", logo.contains(bar))
            }
            assertFalse("Product logos must not retain the old M monogram", logo.contains("M25,78 V35"))
            assertFalse("Product logos must not retain the old music-note tail", logo.contains("M45,63 V80"))
        }

        val webLogo = File(projectRoot, "web/app/src/assets/logo-mark.svg").readText()
        val transparentLogo = File(appRoot, "src/main/assets/LogoTransparent.svg").readText()
        val svgBars = listOf(
            "M30 39V74",
            "M42 48V74",
            "M54 30V74",
            "M66 43V74",
            "M78 35V74",
        )
        listOf(webLogo, transparentLogo).forEach { logo ->
            svgBars.forEach { bar ->
                assertTrue("SVG logo must use $bar", logo.contains(bar))
            }
            assertFalse("SVG logos must not keep the old M monogram", logo.contains("M25 78V35"))
            assertFalse("SVG logos must not keep the old music-note tail", logo.contains("M45 63V80"))
        }
        assertTrue("Web logo remains theme-aware", webLogo.contains("stroke=\"currentColor\""))
        assertTrue("Transparent logo remains gradient-coloured", transparentLogo.contains("stroke=\"url(#mark)\""))

        val fullLogo = File(appRoot, "src/main/assets/Logo.svg").readText()
        val rootLogo = File(projectRoot, "Logo.svg").readText()
        val favicon = File(projectRoot, "web/app/public/favicon.svg").readText()
        val fullSvgBars = listOf(
            "M176 238V350",
            "M216 272V350",
            "M256 210V350",
            "M296 252V350",
            "M336 226V350",
        )
        listOf(fullLogo, rootLogo, favicon).forEach { logo ->
            fullSvgBars.forEach { bar ->
                assertTrue("Full-size brand artwork must use $bar", logo.contains(bar))
            }
            assertFalse("Full-size logo must not keep the old M monogram", logo.contains("M120 369V166"))
        }
        assertEquals("Root logo and web favicon must stay identical", rootLogo, favicon)

        val tvBanner = File(projectRoot, "tv/src/main/res/drawable/tv_banner.xml").readText()
        listOf(
            "M190,130 V186",
            "M223,150 V186",
            "M256,116 V186",
            "M289,142 V186",
            "M322,126 V186",
        ).forEach { bar ->
            assertTrue("TV banner must use the equalizer mark $bar", tvBanner.contains(bar))
        }
        assertFalse("TV banner must not keep the old music-note symbol", tvBanner.contains("M256,73v92"))
    }

    private fun resourcesDir() = File(appRoot, "src/main/res")
}
