part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Pencarian YouTube dan riwayat pencarian.
extension _HomeSearch on _HomePageState {
  void _onSearchTextChanged() {
    final empty = _searchController.text.isEmpty;

    if (empty != _searchTextEmpty && mounted) {
      setState(() {
        _searchTextEmpty = empty;
      });
    }
  }

  void _onSearchFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }


}
