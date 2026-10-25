part of '../youtube_hub.dart';

// The state extensions share private UI logic; State.setState is used by this library.
// ignore_for_file: invalid_use_of_protected_member

/// Pekerjaan awal hub musik yang tidak butuh akun.
extension _YoutubeHubStartupActions on _YoutubeHubState {
  /// Memuat riwayat pencarian dari penyimpanan, lalu memulai pemuatan beranda.
  Future<void> _restore() async {
    final history = await _storage.loadHistory();
    if (!mounted) return;

    setState(() => _searchHistory = history);
    unawaited(_loadHome());
  }
}