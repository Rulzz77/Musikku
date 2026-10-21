// ignore_for_file: invalid_use_of_protected_member

part of '../youtube_hub.dart';

// Non-account startup work for the music hub.
extension _YoutubeHubStartupActions on _YoutubeHubState {
  Future<void> _restore() async {
    final history = await _storage.loadHistory();
    if (!mounted) return;
    setState(() => _searchHistory = history);
    unawaited(_loadHome());
  }
}
