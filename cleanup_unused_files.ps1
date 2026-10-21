$ErrorActionPreference = 'Stop'
$files = @(
  'lib/services/spotify_service.dart',
  'lib/services/subscription_notification_service.dart',
  'lib/services/youtube_live_chat_service.dart',
  'lib/services/youtube_video_service.dart',
  'lib/utils/time_formatters.dart',
  'lib/widgets/hidden_youtube_player.dart',
  'lib/widgets/player_settings_sheet.dart',
  'lib/widgets/youtube_watch_page.dart',
  'lib/widgets/youtube_watch_page/comment_tiles.dart',
  'lib/widgets/youtube_watch_page/live_chat_panel.dart'
)
Write-Host 'File berikut terdeteksi sebagai tidak terhubung ke main.dart:'
$files | ForEach-Object { Write-Host "  $_" }
$answer = Read-Host 'Hapus 10 file di atas dari project ini? Backup project dulu. Ketik HAPUS untuk lanjut'
if ($answer -cne 'HAPUS') { Write-Host 'Dibatalkan; tidak ada file dihapus.'; exit 0 }
foreach ($rel in $files) {
  if (Test-Path -LiteralPath $rel) { Remove-Item -LiteralPath $rel -Force }
}
foreach ($dir in @('lib/widgets/youtube_watch_page','lib/utils')) {
  if (Test-Path -LiteralPath $dir -PathType Container) {
    if (-not (Get-ChildItem -LiteralPath $dir -Force)) { Remove-Item -LiteralPath $dir -Force }
  }
}
Write-Host 'Selesai. Jalankan flutter pub get, lalu flutter analyze.'
