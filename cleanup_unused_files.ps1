$ErrorActionPreference = 'Stop'

# Safe source cleanup for MusikKu v4.8.24+78. Run from the Flutter project root.
if (-not (Test-Path -LiteralPath 'pubspec.yaml' -PathType Leaf) -or
    -not (Test-Path -LiteralPath 'lib/main.dart' -PathType Leaf)) {
  Write-Error 'Folder ini bukan root project Flutter MusikKu. Buka folder yang berisi pubspec.yaml dan lib/main.dart.'
  exit 1
}

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
  'lib/widgets/youtube_watch_page/live_chat_panel.dart',
  'lib/models/youtube_account_models.dart',
  'lib/services/account_request_guard.dart',
  'lib/services/youtube_account_http_client.dart',
  'lib/services/youtube_account_response_parser.dart',
  'lib/services/youtube_account_service.dart',
  'lib/services/youtube_library_api.dart',
  'lib/services/youtube_library_cache.dart',
  'lib/services/youtube_library_repository.dart',
  'lib/services/youtube_login_errors.dart',
  'lib/widgets/youtube_hub/account_actions.dart',
  'android/app/src/main/kotlin/com/musikku/app/SubscriptionWatchWorker.kt',
  # Obsolete tests still targeting the removed Google-account/YouTube-library features.
  'test/account_request_guard_test.dart',
  'test/youtube_library_cache_test.dart',
  'test/youtube_library_repository_test.dart',
  'test/youtube_response_parser_test.dart'
)
$existing = @($files | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($existing.Count -eq 0) {
  Write-Host 'Tidak ada file lama yang perlu dihapus. Tidak ada perubahan.'
  exit 0
}
Write-Host 'File lama/account integration dan test khusus fitur akun yang akan dihapus:'
$existing | ForEach-Object { Write-Host "  $_" }
$answer = Read-Host 'Backup project dahulu. Ketik HAPUS untuk menghapus hanya file yang terdaftar di atas'
if ($answer -cne 'HAPUS') { Write-Host 'Dibatalkan; tidak ada file dihapus.'; exit 0 }
foreach ($rel in $existing) { Remove-Item -LiteralPath $rel -Force }
foreach ($dir in @(
  'lib/widgets/youtube_watch_page',
  'lib/widgets/youtube_hub',
  'lib/utils',
  'lib/services',
  'lib/models',
  'android/app/src/main/kotlin/com/musikku/app'
)) {
  if (Test-Path -LiteralPath $dir -PathType Container) {
    if (-not (Get-ChildItem -LiteralPath $dir -Force)) { Remove-Item -LiteralPath $dir -Force }
  }
}
Write-Host 'Selesai. Jalankan flutter pub get lalu flutter analyze. GeneratedPluginRegistrant akan diperbarui oleh Flutter; jangan edit manual.'
