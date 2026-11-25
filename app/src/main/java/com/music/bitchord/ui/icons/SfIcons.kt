package com.music.bitchord.ui.icons

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.VectorGroup
import androidx.compose.ui.graphics.vector.VectorPath
import androidx.compose.ui.unit.dp

/**
 * Stable semantic icon names for settings and menus.
 *
 * These use the rounded Compose Material vector set, already included by the
 * app. Keeping this wrapper means existing call sites do not need to change
 * when the underlying icon artwork is updated.
 */
object SfIcons {
    // ---- Settings ----
    val AccountPlaceholder: ImageVector by lazy { Icons.Rounded.AccountCircle }
    val Add: ImageVector by lazy { Icons.Rounded.Add }
    val Animation: ImageVector by lazy { Icons.Rounded.AutoAwesome }
    val Appearance: ImageVector by lazy { Icons.Rounded.Brush }
    val Apps: ImageVector by lazy { Icons.Rounded.Apps }
    val ArrowBack: ImageVector by lazy { Icons.Rounded.ArrowBack }
    val AutoAwesome: ImageVector by lazy { Icons.Rounded.AutoAwesome }
    val BarChart: ImageVector by lazy { Icons.Rounded.BarChart }
    val Bluetooth: ImageVector by lazy { Icons.Rounded.Headphones }
    val BlurOff: ImageVector by lazy { Icons.Rounded.BlurOff }
    val BlurOn: ImageVector by lazy { Icons.Rounded.BlurOn }
    val Brightness: ImageVector by lazy { Icons.Rounded.Brightness6 }
    val Cached: ImageVector by lazy { Icons.Rounded.Cached }
    val Check: ImageVector by lazy { Icons.Rounded.Check }
    val ChevronRight: ImageVector by lazy { Icons.Rounded.ChevronRight }
    val Clock: ImageVector by lazy { Icons.Rounded.AccessTime }
    val Cloud: ImageVector by lazy { Icons.Rounded.Cloud }
    val CloudDone: ImageVector by lazy { Icons.Rounded.CloudDone }
    val CloudOff: ImageVector by lazy { Icons.Rounded.CloudOff }
    val ContentCopy: ImageVector by lazy { Icons.Rounded.ContentCopy }
    val DeleteSweep: ImageVector by lazy { Icons.Rounded.DeleteSweep }
    val Dns: ImageVector by lazy { Icons.Rounded.Dns }
    val Download: ImageVector by lazy { Icons.Rounded.Download }
    val DragHandle: ImageVector by lazy { Icons.Rounded.DragHandle }
    val Draw: ImageVector by lazy { Icons.Rounded.Edit }
    val ErrorOutline: ImageVector by lazy { Icons.Rounded.ErrorOutline }
    val Extension: ImageVector by lazy { Icons.Rounded.Extension }
    val FileDownload: ImageVector by lazy { Icons.Rounded.FileDownload }
    val FileDownloadOff: ImageVector by lazy { Icons.Rounded.CloudOff }
    val FileUpload: ImageVector by lazy { Icons.Rounded.FileUpload }
    val FilterAlt: ImageVector by lazy { Icons.Rounded.FilterList }
    val Folder: ImageVector by lazy { Icons.Rounded.Folder }
    val Font: ImageVector by lazy { Icons.Rounded.TextFields }
    val FrameRate: ImageVector by lazy { Icons.Rounded.Speed }
    val Fullscreen: ImageVector by lazy { Icons.Rounded.Fullscreen }
    val Gradient: ImageVector by lazy { Icons.Rounded.Gradient }
    val GraphicEq: ImageVector by lazy { Icons.Rounded.GraphicEq }
    val Groups: ImageVector by lazy { Icons.Rounded.Groups }
    val History: ImageVector by lazy { Icons.Rounded.History }
    val Key: ImageVector by lazy { Icons.Rounded.Key }
    val Label: ImageVector by lazy { Icons.Rounded.Label }
    val Language: ImageVector by lazy { Icons.Rounded.Language }
    val LibraryMusic: ImageVector by lazy { Icons.Rounded.LibraryMusic }
    val LocalOffer: ImageVector by lazy { Icons.Rounded.LocalOffer }
    val Lock: ImageVector by lazy { Icons.Rounded.Lock }
    val Login: ImageVector by lazy { Icons.Rounded.Login }
    val Logout: ImageVector by lazy { Icons.Rounded.Logout }
    val Miscellaneous: ImageVector by lazy { Icons.Rounded.MoreHoriz }
    val MotionPhotosOff: ImageVector by lazy { Icons.Rounded.MotionPhotosOff }
    val MusicNote: ImageVector by lazy { Icons.Rounded.MusicNote }
    val MusicOff: ImageVector by lazy { Icons.Rounded.MusicOff }
    val Notes: ImageVector by lazy { Icons.Rounded.Notes }
    val Performance: ImageVector by lazy { Icons.Rounded.Speed }
    val Person: ImageVector by lazy { Icons.Rounded.Person }
    val PlayCircle: ImageVector by lazy { Icons.Rounded.PlayCircle }
    val PlaylistPlay: ImageVector by lazy { Icons.Rounded.PlaylistPlay }
    val RadioButtonChecked: ImageVector by lazy { Icons.Rounded.RadioButtonChecked }
    val Settings: ImageVector by lazy { Icons.Rounded.Settings }
    val Share: ImageVector by lazy { Icons.Rounded.Share }
    val ShowChart: ImageVector by lazy { Icons.Rounded.ShowChart }
    val SignalCellularAlt: ImageVector by lazy { Icons.Rounded.SignalCellularAlt }
    val SmartButton: ImageVector by lazy { Icons.Rounded.TouchApp }
    val Storage: ImageVector by lazy { Icons.Rounded.Storage }
    val SurroundSound: ImageVector by lazy { Icons.Rounded.SurroundSound }
    val SwitchAccount: ImageVector by lazy { Icons.Rounded.AccountCircle }
    val Translate: ImageVector by lazy { Icons.Rounded.Translate }
    val Tune: ImageVector by lazy { Icons.Rounded.Tune }
    val Usb: ImageVector by lazy { Icons.Rounded.Usb }
    val VisibilityOff: ImageVector by lazy { Icons.Rounded.VisibilityOff }
    val VolumeOff: ImageVector by lazy { Icons.Rounded.VolumeOff }
    val VolumeUp: ImageVector by lazy { Icons.Rounded.VolumeUp }
    val Warning: ImageVector by lazy { Icons.Rounded.Warning }
    val Watch: ImageVector by lazy { Icons.Rounded.Watch }
    val Waves: ImageVector by lazy { Icons.Rounded.Waves }
    val WebAssetOff: ImageVector by lazy { Icons.Rounded.WebAsset }
    val Wifi: ImageVector by lazy { Icons.Rounded.Wifi }
    val YourData: ImageVector by lazy { Icons.Rounded.Archive }

    // ---- Menus ----
    val AddToPlaylist: ImageVector by lazy { Icons.Rounded.PlaylistAdd }
    val Album: ImageVector by lazy { Icons.Rounded.Album }
    val Artist: ImageVector by lazy { Icons.Rounded.Mic }
    val Bug: ImageVector by lazy { Icons.Rounded.BugReport }
    val Close: ImageVector by lazy { Icons.Rounded.Close }
    val Downloaded: ImageVector by lazy { Icons.Rounded.CheckCircle }
    val Heart: ImageVector by lazy { Icons.Rounded.FavoriteBorder }
    val HeartFill: ImageVector by lazy { Icons.Rounded.Favorite }
    val Info: ImageVector by lazy { Icons.Rounded.Info }
    val Open: ImageVector by lazy { Icons.Rounded.ChevronRight }
    val Pencil: ImageVector by lazy { Icons.Rounded.Edit }
    val Pin: ImageVector by lazy { Icons.Rounded.PushPin }
    val Play: ImageVector by lazy { Icons.Rounded.PlayArrow }
    val PlayLast: ImageVector by lazy { Icons.Rounded.QueueMusic }
    val PlayNext: ImageVector by lazy { Icons.Rounded.PlaylistPlay }
    val Radio: ImageVector by lazy { Icons.Rounded.Radio }
    val RemoveFromPlaylist: ImageVector by lazy { Icons.Rounded.PlaylistRemove }
    val Reorder: ImageVector by lazy { Icons.Rounded.SwapVert }
    val Revert: ImageVector by lazy { Icons.Rounded.Replay }
    val Shuffle: ImageVector by lazy { Icons.Rounded.Shuffle }
    val SleepTimer: ImageVector by lazy { Icons.Rounded.Bedtime }
    val Sliders: ImageVector by lazy { Icons.Rounded.Tune }
    val Star: ImageVector by lazy { Icons.Rounded.StarBorder }
    val StarFill: ImageVector by lazy { Icons.Rounded.Star }
    val Trash: ImageVector by lazy { Icons.Rounded.Delete }
    val Upgrade: ImageVector by lazy { Icons.Rounded.AutoAwesome }
    val Upload: ImageVector by lazy { Icons.Rounded.Upload }
    val Video: ImageVector by lazy { Icons.Rounded.VideoLibrary }

    internal const val BOLD_STROKE = 0.9f

    /** Shared square canvas for any custom vector paths drawn by this wrapper. */
    internal const val CANVAS = 31f

    /** A [width]×[height] drawing, in symbol units, centred on the shared canvas. */
    internal inline fun canvas(
        name: String,
        width: Float,
        height: Float,
        autoMirror: Boolean = false,
        content: ImageVector.Builder.() -> Unit,
    ): ImageVector {
        val fit = minOf(1f, CANVAS / width, CANVAS / height)
        return ImageVector.Builder(
            name = name,
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = CANVAS,
            viewportHeight = CANVAS,
            autoMirror = autoMirror,
        ).apply {
            addGroup(
                translationX = (CANVAS - width * fit) / 2f,
                translationY = (CANVAS - height * fit) / 2f,
                scaleX = fit,
                scaleY = fit,
            )
            content()
            clearGroup()
        }.build()
    }

    /** Copies a vector tree while preserving its transforms and path styling. */
    internal fun copyInto(builder: ImageVector.Builder, group: VectorGroup, extraStroke: Float = BOLD_STROKE) {
        for (node in group) {
            when (node) {
                is VectorGroup -> {
                    builder.addGroup(
                        name = node.name,
                        rotate = node.rotation,
                        pivotX = node.pivotX,
                        pivotY = node.pivotY,
                        scaleX = node.scaleX,
                        scaleY = node.scaleY,
                        translationX = node.translationX,
                        translationY = node.translationY,
                        clipPathData = node.clipPathData,
                    )
                    copyInto(builder, node, extraStroke)
                    builder.clearGroup()
                }
                is VectorPath -> builder.addPath(
                    pathData = node.pathData,
                    pathFillType = node.pathFillType,
                    name = node.name,
                    fill = node.fill,
                    fillAlpha = 1f,
                    // A filled shape's outline traced in its own colour: every
                    // line grows by the stroke's width, half on each side.
                    stroke = node.stroke ?: node.fill,
                    strokeAlpha = 1f,
                    strokeLineWidth = node.strokeLineWidth + extraStroke,
                    strokeLineCap = node.strokeLineCap,
                    strokeLineJoin = StrokeJoin.Round,
                    strokeLineMiter = node.strokeLineMiter,
                )
            }
        }
    }
}
