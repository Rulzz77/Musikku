package com.music.bitchord

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * The eight home-screen styles shown in Settings. They share one equalizer
 * silhouette; only the background treatment and bar colours change.
 */
enum class AppIcon(
    val alias: String,
    val iconRes: Int,
    val labelRes: Int,
    val previewRes: Int,
) {
    Default("LauncherDefault", R.mipmap.ic_launcher, R.string.app_icon_default, R.drawable.ic_variant_default),
    Monochrome("LauncherMonochrome", R.mipmap.ic_monochrome, R.string.app_icon_monochrome, R.drawable.ic_variant_monochrome),
    LiquidGlass("LauncherGlassLight", R.mipmap.ic_liquid_glass, R.string.app_icon_liquid_glass, R.drawable.ic_variant_liquid_glass),
    LiquidGlassDark("LauncherGlassDark", R.mipmap.ic_liquid_glass_dark, R.string.app_icon_liquid_glass_dark, R.drawable.ic_variant_liquid_glass_dark),
    LiquidGlassClear("LauncherGlassClear", R.mipmap.ic_liquid_glass_clear, R.string.app_icon_liquid_glass_clear, R.drawable.ic_variant_liquid_glass_clear),
    NeonSilver("LauncherNeonSilver", R.mipmap.ic_neon_silver, R.string.app_icon_neon_silver, R.drawable.ic_variant_neon_silver),
    NeonCyan("LauncherNeonCyan", R.mipmap.ic_neon_cyan, R.string.app_icon_neon_cyan, R.drawable.ic_variant_neon_cyan),
    NeonViolet("LauncherNeonViolet", R.mipmap.ic_neon_violet, R.string.app_icon_neon_violet, R.drawable.ic_variant_neon_violet);

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

        /** Enable the new alias before disabling the others to avoid a missing launcher entry. */
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
