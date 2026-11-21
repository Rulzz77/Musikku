package com.music.bitchord.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/**
 * A compact broken-heart vector used by the dislike action.
 *
 * It is drawn locally with Compose paths so the icon does not depend on a
 * separately distributed symbol pack. The two halves share the familiar heart
 * silhouette and leave a narrow zig-zag split through the middle.
 */
object BrokenHeart {
    val Outline: ImageVector by lazy { create("bc_broken_heart", filled = false) }
    val Fill: ImageVector by lazy { create("bc_broken_heart_fill", filled = true) }

    private const val LEFT_HALF =
        "M 12 21 C 10.8 19.8 2 13.5 2 8.3 C 2 5.2 4.3 3 7.1 3 " +
        "C 9.2 3 11 4.4 12 6.2 L 10.7 9.1 L 11.7 11.2 " +
        "L 10.5 14 L 11.4 16 L 11.3 18.1 Z"

    private const val RIGHT_HALF =
        "M 12 21 C 13.2 19.8 22 13.5 22 8.3 C 22 5.2 19.7 3 16.9 3 " +
        "C 14.8 3 13 4.4 12 6.2 L 13.3 9.1 L 12.3 11.2 " +
        "L 13.5 14 L 12.6 16 L 12.7 18.1 Z"

    private fun create(name: String, filled: Boolean): ImageVector {
        val iconColor = SolidColor(Color.Black)
        return ImageVector.Builder(
            name = name,
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            listOf(LEFT_HALF, RIGHT_HALF).forEach { path ->
                addPath(
                    pathData = addPathNodes(path),
                    pathFillType = PathFillType.NonZero,
                    fill = if (filled) iconColor else null,
                    fillAlpha = 1f,
                    stroke = if (filled) null else iconColor,
                    strokeAlpha = 1f,
                    strokeLineWidth = if (filled) 0f else 1.8f,
                    strokeLineCap = StrokeCap.Round,
                    strokeLineJoin = StrokeJoin.Round,
                )
            }
        }.build()
    }
}
