part of '../youtube_hub.dart';

// The state extensions share private UI logic; State.setState is used by this library.
// ignore_for_file: invalid_use_of_protected_member

extension _YoutubeHubAccountActions on _YoutubeHubState {
  /// Pulihkan sesi Google secara silent saat aplikasi dibuka kembali.
  /// Tidak membuka pemilih akun; kalau sesi tidak bisa dipulihkan, pengguna
  /// tetap bisa masuk manual dari ikon akun.
  Future<void> _restore() async {
    final history = await _storage.loadHistory();
    final rememberedEmail = await _account.rememberedAccountEmail();
    if (mounted) {
      setState(() {
        _searchHistory = history;
        _rememberedAccountEmail = rememberedEmail ?? '';
      });
    }
    // Tampilkan snapshot YouTube yang tersimpan terlebih dahulu agar Koleksi,
    // Likes, Playlist, dan feed subscription tidak harus menunggu jaringan.
    if (rememberedEmail != null && rememberedEmail.trim().isNotEmpty) {
      await _loadAccountCache(rememberedEmail);
    }
    unawaited(_loadHome());
    try {
      await _account.tryRestoreSession();
    } catch (e) {
      debugPrint('SILENT GOOGLE SESSION RESTORE ERROR: $e');
    }
    if (!mounted) return;
    final restoredUser = _account.user;
    final restoredEmail = restoredUser?.email.trim() ?? '';
    final displayedEmail = _rememberedAccountEmail.trim().toLowerCase();
    if (restoredEmail.isNotEmpty &&
        displayedEmail.isNotEmpty &&
        restoredEmail.toLowerCase() != displayedEmail) {
      await _resetVisibleAccountLibrary(restoredEmail);
    }
    if (!mounted) return;
    setState(() {
      _user = restoredUser;
      if (restoredUser != null && restoredUser.email.isNotEmpty) {
        _rememberedAccountEmail = restoredUser.email;
      }
    });
    if (_account.isSignedIn) {
      unawaited(_run(_refreshAccount));
    }
  }

  Future<void> _resetVisibleAccountLibrary(String email) async {
    if (!mounted) return;
    setState(() {
      _subscriptions = const [];
      _liked = const [];
      _playlists = const [];
      _subscriptionFeed = const [];
      _selectedPlaylist = null;
      _playlistItems = const [];
      _rememberedAccountEmail = email;
    });
    await _loadAccountCache(email);
  }

  Future<void> _loadAccountCache(String email) async {
    final cacheLoadSequence = ++_accountCacheLoadSequence;
    final snapshot = await _libraryRepository.loadCached(email);
    if (!mounted ||
        !snapshot.hasData ||
        cacheLoadSequence != _accountCacheLoadSequence) {
      return;
    }
    // A cached snapshot belongs to one account only. Never apply it if the
    // remembered identity changed while SharedPreferences was being read.
    final currentEmail = _account.user?.email.trim().toLowerCase() ?? '';
    final remembered = _rememberedAccountEmail.trim().toLowerCase();
    if (currentEmail.isNotEmpty && currentEmail != email.trim().toLowerCase()) {
      return;
    }
    if (remembered.isNotEmpty && remembered != email.trim().toLowerCase()) {
      return;
    }
    setState(() {
      if (snapshot.subscriptions != null) _subscriptions = snapshot.subscriptions!;
      if (snapshot.likedVideos != null) _liked = snapshot.likedVideos!;
      if (snapshot.playlists != null) _playlists = snapshot.playlists!;
      if (snapshot.feed != null) {
        _subscriptionFeed = _visibleSubscriptionFeed(snapshot.feed!);
      }
    });
  }

  Future<void> _refreshSubscriptionInBackground() async {
    if (!mounted || !_account.isSignedIn) return;
    if (widget.settings.prefetchWifiOnly.value) {
      final type = await NativeYoutubeController().getNetworkType();
      if (type != 'wifi' && type != 'ethernet') {
        return;
      }
    }
    await _refreshFeedOnly();
  }

  List<YoutubeSearchResult> _visibleSubscriptionFeed(
    List<YoutubeSearchResult> feed,
  ) {
    final musicFeed = feed
        .where((video) => YoutubeSearchService.isMusicCatalogItem(
              video,
              requireCategoryId: true,
            ))
        .toList(growable: false);
    final live = musicFeed.where((video) => video.isLive).toList(growable: false);
    final regular = musicFeed
        .where((video) => !video.isLive && !video.isUpcoming)
        .toList(growable: false);
    return [...live, ...regular].take(30).toList(growable: false);
  }

  Future<void> _refreshAccount() async {
    if (!_account.isSignedIn) return;
    if (_account.needsInteractiveAuthorization) {
      if (mounted) setState(() => _needsAuthorization = true);
      return;
    }

    final email = _account.user?.email.trim() ?? '';
    if (email.isEmpty) return;
    // A network refresh supersedes any cache read that started before it; this
    // prevents a slower cache snapshot from overwriting fresher API results.
    _accountCacheLoadSequence++;
    final accountGeneration = _accountRequestGuard.observe(email);
    final refreshSequence = ++_accountRefreshSequence;
    // A full library refresh supersedes older feed-only requests.
    final feedSequence = ++_feedRefreshSequence;

    bool isSameAccount() =>
        _accountRequestGuard.isCurrent(
          generation: accountGeneration,
          expectedEmail: email,
          activeEmail: _account.user?.email,
          isMounted: mounted && _account.isSignedIn,
        ) &&
        refreshSequence == _accountRefreshSequence;

    await for (final update in _libraryRepository.refresh(
      email,
      isStillActive: isSameAccount,
    )) {
      if (!isSameAccount()) continue;
      final subscriptions = update.subscriptions;
      final likedVideos = update.likedVideos;
      final playlists = update.playlists;
      final feed = update.feed;
      if (subscriptions != null) {
        setState(() => _subscriptions = subscriptions);
      }
      if (likedVideos != null) {
        setState(() => _liked = likedVideos);
      }
      if (playlists != null) {
        setState(() => _playlists = playlists);
      }
      if (feed != null && feedSequence == _feedRefreshSequence) {
        await _applyFeed(
          feed,
          expectedEmail: email,
          accountGeneration: accountGeneration,
          feedSequence: feedSequence,
          accountRefreshSequence: refreshSequence,
        );
      }
    }
  }

  /// Hanya menyegarkan feed + status live (tanpa memuat ulang playlist/likes).
  Future<void> _refreshFeedOnly() async {
    if (!_account.isSignedIn || _account.needsInteractiveAuthorization) return;
    final email = _account.user?.email.trim() ?? '';
    if (email.isEmpty || _subscriptions.isEmpty) return;
    final accountGeneration = _accountRequestGuard.observe(email);
    final feedSequence = ++_feedRefreshSequence;
    final subscriptions = List<YoutubeChannelSummary>.unmodifiable(_subscriptions);
    bool isCurrent() =>
        _accountRequestGuard.isCurrent(
          generation: accountGeneration,
          expectedEmail: email,
          activeEmail: _account.user?.email,
          isMounted: mounted && _account.isSignedIn,
        ) &&
        feedSequence == _feedRefreshSequence;
    try {
      final feed = await _libraryRepository.refreshFeed(
        email,
        subscriptions,
        isStillActive: isCurrent,
      );
      if (!isCurrent()) return;
      await _applyFeed(
        feed,
        expectedEmail: email,
        accountGeneration: accountGeneration,
        feedSequence: feedSequence,
      );
    } catch (e) {
      debugPrint('YOUTUBE FEED REFRESH ERROR: $e');
    }
  }

  /// Applies a feed only while the account that requested it remains active.
  /// This prevents a slow request from account A being written into account B's
  /// UI or cache after a sign-out / account switch.
  Future<void> _applyFeed(
    List<YoutubeSearchResult> feed, {
    required String expectedEmail,
    required int accountGeneration,
    required int feedSequence,
    int? accountRefreshSequence,
  }) async {
    bool isCurrent() =>
        _accountRequestGuard.isCurrent(
          generation: accountGeneration,
          expectedEmail: expectedEmail,
          activeEmail: _account.user?.email,
          isMounted: mounted && _account.isSignedIn,
        ) &&
        feedSequence == _feedRefreshSequence &&
        (accountRefreshSequence == null ||
            accountRefreshSequence == _accountRefreshSequence);
    if (!isCurrent()) return;

    final visibleFeed = _visibleSubscriptionFeed(feed);
    if (!isCurrent()) return;
    setState(() => _subscriptionFeed = visibleFeed);
  }

  Future<void> _restoreAccountAfterUserAction() async {
    try {
      final previousEmail = (_user?.email ?? _rememberedAccountEmail)
          .trim()
          .toLowerCase();
      await _account.tryRestoreSession();
      if (!mounted || !_account.isSignedIn) return;
      final restoredUser = _account.user;
      final restoredEmail = restoredUser?.email.trim() ?? '';
      if (restoredEmail.isNotEmpty &&
          restoredEmail.toLowerCase() != previousEmail) {
        _accountRequestGuard.invalidate();
        _accountRefreshSequence++;
        _accountCacheLoadSequence++;
        _feedRefreshSequence++;
        _playlistRequestSequence++;
        await _resetVisibleAccountLibrary(restoredEmail);
      }
      if (!mounted) return;
      setState(() {
        _user = restoredUser;
        if (restoredEmail.isNotEmpty) {
          _rememberedAccountEmail = restoredEmail;
        }
      });
      await _run(_refreshAccount);
    } catch (e) {
      debugPrint('GOOGLE RESTORE AFTER USER ACTION ERROR: $e');
    }
  }

  Future<void> _login() async {
    await _run(() async {
      final previousEmail = (_account.user?.email ?? _rememberedAccountEmail)
          .trim()
          .toLowerCase();
      _accountRequestGuard.invalidate();
      _accountRefreshSequence++;
      _accountCacheLoadSequence++;
      _feedRefreshSequence++;
      _playlistRequestSequence++;
      // Dipanggil hanya dari tap pengguna. Kalau pernah login, coba pulihkan
      // akun tersimpan dulu; kalau belum, tampilkan pemilih akun Google.
      await _account.tryRestoreSession();
      if (_account.user == null) {
        _user = await _account.signIn();
      } else {
        _user = _account.user;
        if (_account.needsInteractiveAuthorization) {
          await _account.authorizeYouTubeAccess();
        }
      }
      final activeEmail = _account.user?.email.trim() ?? '';
      if (mounted) {
        setState(() {
          _needsAuthorization = false;
          _rememberedAccountEmail = activeEmail.isNotEmpty
              ? activeEmail
              : _rememberedAccountEmail;
        });
      }
      if (activeEmail.isNotEmpty &&
          activeEmail.toLowerCase() != previousEmail) {
        await _resetVisibleAccountLibrary(activeEmail);
      }
      await _refreshAccount();
    });
  }

  Future<void> _authorizeYoutube() async {
    await _run(() async {
      final ok = await _account.authorizeYouTubeAccess();
      if (!ok) throw StateError('Akun Google belum tersedia.');
      if (mounted) setState(() => _needsAuthorization = false);
      await _refreshAccount();
    });
  }

  Future<void> _logout() async {
    await _run(() async {
      _accountRequestGuard.invalidate();
      _accountRefreshSequence++;
      _accountCacheLoadSequence++;
      _feedRefreshSequence++;
      _playlistRequestSequence++;
      final signedOutEmail = _account.user?.email ?? _rememberedAccountEmail;
      await _account.signOut();
      await _libraryRepository.clearCached(signedOutEmail);
      unawaited(NativeYoutubeController.configureBackgroundWatch(enabled: false));
      if (!mounted) return;
      setState(() {
        _user = null;
        _subscriptions = const [];
        _liked = const [];
        _playlists = const [];
        _selectedPlaylist = null;
        _playlistItems = const [];
        _subscriptionFeed = const [];
        _rememberedAccountEmail = '';
      });
    });
  }

  /// Dipanggil halaman channel setelah subscribe/unsubscribe. Kalau pengguna
  /// baru login dari halaman channel, status login hub ikut diperbarui.
  void _onChannelSubscriptionChanged() {
    if (!mounted) return;
    final currentUser = _account.user;
    final currentEmail = currentUser?.email.trim() ?? '';
    final displayedEmail = (_user?.email ?? _rememberedAccountEmail)
        .trim()
        .toLowerCase();
    if (currentUser != null &&
        currentEmail.isNotEmpty &&
        currentEmail.toLowerCase() != displayedEmail) {
      _accountRequestGuard.invalidate();
      unawaited(_resetVisibleAccountLibrary(currentEmail));
      setState(() => _user = currentUser);
    } else if (_account.isSignedIn && _user == null) {
      setState(() => _user = currentUser);
    }
    unawaited(_run(_refreshAccount));
  }

  void _openChannel(YoutubeChannelSummary channel) {
    _handleControllerOpenChannel(channel.id, channel.title, channel.thumbnailUrl);
  }

  void _openAllSubscriptions() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => YoutubeSubscriptionsPage(
          channels: _subscriptions,
          onOpen: (channel) {
            // Tutup daftar dulu, lalu channel terbuka sebagai lapisan hub.
            Navigator.of(routeContext).pop();
            _openChannel(channel);
          },
        ),
      ),
    );
  }

  Future<void> _openPlaylist(YoutubePlaylistSummary playlist) async {
    await _run(() async {
      final email = _account.user?.email.trim() ?? '';
      if (email.isEmpty) return;
      final accountGeneration = _accountRequestGuard.observe(email);
      final requestSequence = ++_playlistRequestSequence;
      final videos = await _libraryRepository.loadPlaylistItems(playlist.id);
      final stillCurrent = _accountRequestGuard.isCurrent(
        generation: accountGeneration,
        expectedEmail: email,
        activeEmail: _account.user?.email,
        isMounted: mounted && _account.isSignedIn,
      ) && requestSequence == _playlistRequestSequence;
      if (!stillCurrent) return;
      setState(() {
        _selectedPlaylist = playlist;
        _playlistItems = videos;
      });
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_loading) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      await task();
    } catch (e) {
      if (!mounted) return;
      debugPrint('YOUTUBE HUB ERROR: $e');
      setState(() => _error = describeLoginError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
