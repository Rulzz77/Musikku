package com.music.bitchord

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * The home-screen icon choices. Each is an `<activity-alias>` in the manifest
 * carrying the launcher intent filter; exactly one is enabled at a time.
 *
 * The glass icons are adaptive icons whose foreground already holds the finished
 * icon in its own shape (Apple squircle, Samsung squircle or Pixel circle), so
 * [previewRes] — that foreground — shows the variant as designed rather than
 * through the device's launcher mask. The first two keep yesterday's alias
 * names so a choice made before the update stays enabled.
 */
enum class AppIcon(val alias: String, val iconRes: Int, val labelRes: Int, val previewRes: Int? = null) {
    Default("LauncherDefault", R.mipmap.ic_launcher, R.string.app_icon_default),
    Monochrome("LauncherMonochrome", R.mipmap.ic_monochrome, R.string.app_icon_monochrome, R.drawable.ic_musikku_monochrome),
    LiquidGlass("LauncherGlassLight", R.mipmap.ic_liquid_glass, R.string.app_icon_liquid_glass, R.drawable.ic_variant_liquid_glass),
    LiquidGlassDark("LauncherGlassDark", R.mipmap.ic_liquid_glass_dark, R.string.app_icon_liquid_glass_dark, R.drawable.ic_variant_liquid_glass_dark),
    LiquidGlassClear("LauncherGlassClear", R.mipmap.ic_liquid_glass_clear, R.string.app_icon_liquid_glass_clear, R.drawable.ic_variant_liquid_glass_clear),
    LiquidGlassClearDark("LauncherGlassClearDark", R.mipmap.ic_liquid_glass_clear_dark, R.string.app_icon_liquid_glass_clear_dark, R.drawable.ic_variant_liquid_glass_clear_dark),
    SamsungGlass("LauncherSamsungGlass", R.mipmap.ic_samsung_glass, R.string.app_icon_samsung_glass, R.drawable.ic_variant_samsung_glass),
    SamsungGlassDark("LauncherSamsungGlassDark", R.mipmap.ic_samsung_glass_dark, R.string.app_icon_samsung_glass_dark, R.drawable.ic_variant_samsung_glass_dark),
    SamsungGlassClear("LauncherSamsungGlassClear", R.mipmap.ic_samsung_glass_clear, R.string.app_icon_samsung_glass_clear, R.drawable.ic_variant_samsung_glass_clear),
    SamsungGlassClearDark("LauncherSamsungGlassClearDark", R.mipmap.ic_samsung_glass_clear_dark, R.string.app_icon_samsung_glass_clear_dark, R.drawable.ic_variant_samsung_glass_clear_dark),
    PixelGlass("LauncherPixelGlass", R.mipmap.ic_pixel_glass, R.string.app_icon_pixel_glass, R.drawable.ic_variant_pixel_glass),
    PixelGlassDark("LauncherPixelGlassDark", R.mipmap.ic_pixel_glass_dark, R.string.app_icon_pixel_glass_dark, R.drawable.ic_variant_pixel_glass_dark),
    PixelGlassClear("LauncherPixelGlassClear", R.mipmap.ic_pixel_glass_clear, R.string.app_icon_pixel_glass_clear, R.drawable.ic_variant_pixel_glass_clear),
    PixelGlassClearDark("LauncherPixelGlassClearDark", R.mipmap.ic_pixel_glass_clear_dark, R.string.app_icon_pixel_glass_clear_dark, R.drawable.ic_variant_pixel_glass_clear_dark),
    NeonSilver("LauncherNeonSilver", R.mipmap.ic_neon_silver, R.string.app_icon_neon_silver, R.drawable.ic_variant_neon_silver),
    NeonCyan("LauncherNeonCyan", R.mipmap.ic_neon_cyan, R.string.app_icon_neon_cyan, R.drawable.ic_variant_neon_cyan),
    NeonViolet("LauncherNeonViolet", R.mipmap.ic_neon_violet, R.string.app_icon_neon_violet, R.drawable.ic_variant_neon_violet),
    SamsungNeonSilver("LauncherSamsungNeonSilver", R.mipmap.ic_samsung_neon_silver, R.string.app_icon_samsung_neon_silver, R.drawable.ic_variant_samsung_neon_silver),
    SamsungNeonCyan("LauncherSamsungNeonCyan", R.mipmap.ic_samsung_neon_cyan, R.string.app_icon_samsung_neon_cyan, R.drawable.ic_variant_samsung_neon_cyan),
    SamsungNeonViolet("LauncherSamsungNeonViolet", R.mipmap.ic_samsung_neon_violet, R.string.app_icon_samsung_neon_violet, R.drawable.ic_variant_samsung_neon_violet),
    PixelNeonSilver("LauncherPixelNeonSilver", R.mipmap.ic_pixel_neon_silver, R.string.app_icon_pixel_neon_silver, R.drawable.ic_variant_pixel_neon_silver),
    PixelNeonCyan("LauncherPixelNeonCyan", R.mipmap.ic_pixel_neon_cyan, R.string.app_icon_pixel_neon_cyan, R.drawable.ic_variant_pixel_neon_cyan),
    PixelNeonViolet("LauncherPixelNeonViolet", R.mipmap.ic_pixel_neon_violet, R.string.app_icon_pixel_neon_violet, R.drawable.ic_variant_pixel_neon_violet);

    private fun component(context: Context) =
        ComponentName(context.packageName, "com.music.bitchord.$alias")

    companion object {
        fun current(context: Context): AppIcon {
            val pm = context.packageManager
            return entries.firstOrNull {
                pm.getComponentEnabledSetting(it.component(context)) ==
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } ?: Default
        }

        /** Enables [icon] before disabling the rest so there is never a moment with no launcher entry. */
        fun apply(context: Context, icon: AppIcon) {
            val pm = context.packageManager
            pm.setComponentEnabledSetting(
                icon.component(context),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            entries.filter { it != icon }.forEach {
                pm.setComponentEnabledSetting(
                    it.component(context),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
        }
    }
}
