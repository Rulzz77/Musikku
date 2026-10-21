import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/youtube_search_result.dart';
import '../models/youtube_account_models.dart';
import 'youtube_library_api.dart';
import 'youtube_account_http_client.dart';
import 'youtube_account_response_parser.dart';
import 'youtube_search_service.dart';
import 'disk_cache.dart';

export '../models/youtube_account_models.dart';
export 'youtube_library_api.dart';
export 'youtube_login_errors.dart' show describeLoginError;

class YoutubeAccountService implements YoutubeLibraryApi {
  static final YoutubeAccountService instance = YoutubeAccountService._();

  YoutubeAccountService._();

  static const _scopeReadonly = 'https://www.googleapis.com/auth/youtube.readonly';
  static const _scopeManage = 'https://www.googleapis.com/auth/youtube';
  static const _base = 'https://www.googleapis.com/youtube/v3';
  static const _sessionOkKey = 'youtube_session_ok';
  static const _explicitSignOutKey = 'youtube_user_explicitly_signed_out';

  static const DiskCache _uploadPageCache = DiskCache(
    namespace: 'yt_upload_pages_v1',
    maxEntries: 250,
    ttl: Duration(minutes: 30),
  );
  static const DiskCache _enrichedVideoCache = DiskCache(
    namespace: 'yt_enriched_video_batches_v1',
    maxEntries: 80,
    ttl: Duration(hours: 6),
  );

  /// Dipakai untuk data publik (channel, video, playlist upload) saat pengguna
  /// belum login, jadi halaman channel bisa dibuka tanpa akun Google.
  static const String _apiKey = String.fromEnvironment('YOUTUBE_API_KEY');

  /// Minta scope YouTube saat login mobile. Di Android versi plugin 7.x
  /// memakai Credential Manager yang tidak menjamin silent re-auth; versi 6.3
  /// menyediakan signInSilently() yang didesain untuk memulihkan sesi tanpa UI.
  static const _allScopes = <String>[_scopeReadonly, _scopeManage];

  late final GoogleSignIn _signIn;
  GoogleSignInAccount? _user;
  bool _initialized = false;
  Future<void> _sessionTail = Future<void>.value();
  StreamSubscription<GoogleSignInAccount?>? _currentUserSubscription;
  bool _readonlyAuthorizationGranted = false;

  late final YoutubeAccountHttpClient _httpClient = YoutubeAccountHttpClient(
    apiKey: _apiKey,
    baseUrl: _base,
    isSignedIn: () => _user != null,
    accessToken: _accessToken,
  );

  GoogleSignInAccount? get user => _user;
  bool get isSignedIn => _user != null;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    final serverClientId = const String.fromEnvironment('YOUTUBE_WEB_CLIENT_ID').trim();
    if (serverClientId.isEmpty) {
      throw StateError(
        'Google Sign-In belum dikonfigurasi. Jalankan dengan '
        '--dart-define=YOUTUBE_WEB_CLIENT_ID=WEB_CLIENT_ID, '
        'atau konfigurasikan OAuth Web client ID untuk package com.musikku.app.',
      );
    }

    _signIn = GoogleSignIn(
      scopes: _allScopes,
      serverClientId: serverClientId,
    );
    _currentUserSubscription ??= _signIn.onCurrentUserChanged.listen(
      (account) => unawaited(_handleCurrentUserChanged(account)),
      onError: (_) {},
    );
    _initialized = true;
  }

  Future<void> _handleCurrentUserChanged(GoogleSignInAccount? account) async {
    if (account != null) {
      _user = account;
      // In Android the configured OAuth scopes are requested during sign-in.
      _readonlyAuthorizationGranted = true;
      try {
        await _rememberUser(account);
        await _setSessionOk(true);
        await _setExplicitSignOut(false);
      } catch (_) {
        // Account state is still usable for this process; persistence can retry
        // on the next successful restore.
      }
      return;
    }

    // A null stream value is also emitted during initial bootstrap. Preserve
    // saved identity unless an account was actually active in this process.
    final hadActiveUser = _user != null;
    _user = null;
    _readonlyAuthorizationGranted = false;
    if (hadActiveUser) {
      try {
        await _setExplicitSignOut(true);
        await _clearRememberedUser();
      } catch (_) {
        // Do not crash the authentication stream because local cleanup failed.
      }
    }
  }

  Future<GoogleSignInAccount> signIn() async {
    return _serializeSession(() async {
      await _ensureInitialized();
      final account = await _signIn.signIn();
      if (account == null) {
        throw StateError('Login Google dibatalkan.');
      }
      _user = account;
      _readonlyAuthorizationGranted = true;
      await _rememberUser(account);
      await _setSessionOk(true);
      await _setExplicitSignOut(false);
      return account;
    });
  }

  /// Restore the last Google account without opening an interactive login flow.
  /// Unlike google_sign_in 7.x's Android Credential Manager path, the 6.3.0
  /// API exposes signInSilently() for this purpose. Always attempt it: a prior
  /// app version may already have removed the saved email marker on startup.
  Future<void> tryRestoreSession() async {
    await _serializeSession(() async {
      if (_user != null) return;
      await _ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_explicitSignOutKey) ?? false) return;

      try {
        final restored = await _signIn.signInSilently(suppressErrors: true);
        final account = restored ?? _signIn.currentUser ?? _user;
        if (account != null) {
          _user = account;
          _readonlyAuthorizationGranted = true;
          await _rememberUser(account);
          await _setSessionOk(true);
          await _setExplicitSignOut(false);
        }
        // If restore fails, keep the saved identity for the UI and try again
        // next launch instead of deleting the account marker.
      } catch (_) {
        // Silent restore must never open a login UI or break app startup.
      }
    });
  }

  /// Dipertahankan untuk UI yang menampilkan akun terakhir yang diingat.
  Future<bool> hasRestorableSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('youtube_last_account_email') ?? '';
    return email.isNotEmpty && !(prefs.getBool(_explicitSignOutKey) ?? false);
  }

  Future<void> _setSessionOk(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sessionOkKey, value);
  }

  Future<void> _setExplicitSignOut(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_explicitSignOutKey, value);
  }

  Future<void> signOut() async {
    await _serializeSession(() async {
      await _ensureInitialized();
      // Mark this as a deliberate logout before the plugin emits a null account
      // event, preventing silent restore from signing the user straight back in.
      await _setExplicitSignOut(true);
      await _signIn.signOut();
      _user = null;
      _readonlyAuthorizationGranted = false;
      await _clearRememberedUser();
    });
  }

  Future<T> _serializeSession<T>(Future<T> Function() action) {
    final previous = _sessionTail;
    final done = Completer<void>();
    _sessionTail = done.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        done.complete();
      }
    }();
  }

  Future<void> _authorize() async {
    await _ensureInitialized();
    if (_user == null) {
      throw StateError('Belum login ke Google.');
    }
    // For Android, google_sign_in 6.3 authorizes requested scopes as part of
    // native sign-in. The constructor requests both YouTube scopes up front.
    _readonlyAuthorizationGranted = true;
  }

  Future<bool> authorizeYouTubeAccess() async {
    return _serializeSession(() async {
      await _ensureInitialized();
      if (_user == null) return false;
      try {
        final authentication = await _user!.authentication;
        return authentication.accessToken?.isNotEmpty ?? false;
      } catch (_) {
        return false;
      }
    });
  }

  /// Restore a saved session first; otherwise start interactive sign-in after a user tap.
  Future<void> ensureSignedIn() async {
    await tryRestoreSession();
    if (_user == null) {
      await signIn();
    } else if (needsInteractiveAuthorization) {
      await authorizeYouTubeAccess();
    }
  }

  bool get needsInteractiveAuthorization =>
      _user != null && !_readonlyAuthorizationGranted;

  Future<void> _rememberUser(GoogleSignInAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('youtube_last_account_email', account.email);
    await prefs.setString('youtube_last_account_name', account.displayName ?? '');
  }

  Future<void> _clearRememberedUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('youtube_last_account_email');
    await prefs.remove('youtube_last_account_name');
    await prefs.remove(_sessionOkKey);
  }

  Future<String?> rememberedAccountEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('youtube_last_account_email');
  }

  Future<String> _accessToken({required bool write}) async {
    await _ensureInitialized();
    final account = _user;
    if (account == null) {
      throw StateError('Silakan login Google terlebih dahulu.');
    }
    await _authorize();
    final authentication = await account.authentication;
    final token = authentication.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Token Google belum tersedia. Buka akun dan login kembali.');
    }
    return token;
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> params, {
    required bool write,
  }) => _httpClient.get(path, params, write: write);

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    required bool write,
  }) => _httpClient.post(path, body, write: write);

  Future<void> _delete(
    String path,
    Map<String, String> params, {
    required bool write,
  }) => _httpClient.delete(path, params, write: write);

  @override
  Future<List<YoutubeChannelSummary>> subscriptions({int maxResults = 50}) async {
    // Ambil semua halaman (maks. 4 x 50 = 200 channel) supaya jumlah
    // subscription tidak terpotong di 50.
    final items = <dynamic>[];
    String? pageToken;
    for (var page = 0; page < 4; page++) {
      final params = <String, String>{
        'part': 'snippet,contentDetails',
        'mine': 'true',
        'order': 'alphabetical',
        'maxResults': '$maxResults',
      };
      final token = pageToken;
      if (token != null && token.isNotEmpty) {
        params['pageToken'] = token;
      }
      final data = await _get(
        'subscriptions',
        params,
        write: false,
      );
      final pageItems = data['items'];
      if (pageItems is List) items.addAll(pageItems);
      pageToken = data['nextPageToken']?.toString();
      if (pageToken == null || pageToken.isEmpty) break;
    }
    if (items.isEmpty) return const [];

    final channels = <YoutubeChannelSummary>[];
    for (final item in items) {
      final map = Map<String, dynamic>.from(item as Map);
      final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
      final resource = Map<String, dynamic>.from(snippet['resourceId'] as Map? ?? const {});
      final channelId = resource['channelId']?.toString() ?? '';
      if (channelId.isEmpty) continue;
      channels.add(
        YoutubeChannelSummary(
          id: channelId,
          title: snippet['title']?.toString() ?? 'Channel',
          description: snippet['description']?.toString() ?? '',
          thumbnailUrl: YoutubeAccountResponseParser.thumbnail(snippet['thumbnails']),
          uploadsPlaylistId: '',
        ),
      );
    }

    // Resolve upload playlist ids in one channels.list call per batch.
    final resolved = <YoutubeChannelSummary>[];
    for (var i = 0; i < channels.length; i += 50) {
      final end = (i + 50) < channels.length ? (i + 50) : channels.length;
      final batch = channels.sublist(i, end);
      final data = await _get(
        'channels',
        <String, String>{
          'part': 'snippet,contentDetails,statistics',
          'id': batch.map((e) => e.id).join(','),
          'maxResults': '${batch.length}',
        },
        write: false,
      );
      final items = data['items'];
      if (items is! List) continue;
      for (final item in items) {
        final map = Map<String, dynamic>.from(item as Map);
        final id = map['id']?.toString() ?? '';
        final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
        final content = Map<String, dynamic>.from(map['contentDetails'] as Map? ?? const {});
        final stats = Map<String, dynamic>.from(map['statistics'] as Map? ?? const {});
        final related = Map<String, dynamic>.from(content['relatedPlaylists'] as Map? ?? const {});
        final original = batch.where((e) => e.id == id).firstOrNull;
        resolved.add(
          YoutubeChannelSummary(
            id: id,
            title: snippet['title']?.toString() ?? original?.title ?? 'Channel',
            description: snippet['description']?.toString() ?? original?.description ?? '',
            thumbnailUrl: YoutubeAccountResponseParser.thumbnail(snippet['thumbnails']).isNotEmpty
                ? YoutubeAccountResponseParser.thumbnail(snippet['thumbnails'])
                : (original?.thumbnailUrl ?? ''),
            uploadsPlaylistId: related['uploads']?.toString() ?? '',
            subscriberCount: int.tryParse(stats['subscriberCount']?.toString() ?? ''),
          ),
        );
      }
    }
    return resolved;
  }

  Future<List<YoutubeSearchResult>> channelVideos(
    String channelId, {
    int maxResults = 20,
  }) async {
    if (channelId.trim().isEmpty) return const [];
    final data = await _get(
      'channels',
      <String, String>{
        'part': 'contentDetails,snippet',
        'id': channelId,
        'maxResults': '1',
      },
      write: false,
    );
    final items = data['items'];
    if (items is! List || items.isEmpty) return const [];
    final first = Map<String, dynamic>.from(items.first as Map);
    final channelSnippet = Map<String, dynamic>.from(first['snippet'] as Map? ?? const {});
    final channelTitle = channelSnippet['title']?.toString() ?? '';
    final channelDescription = channelSnippet['description']?.toString() ?? '';
    final content = Map<String, dynamic>.from(first['contentDetails'] as Map? ?? const {});
    final related = Map<String, dynamic>.from(content['relatedPlaylists'] as Map? ?? const {});
    final uploads = related['uploads']?.toString() ?? '';
    if (uploads.isEmpty) return const [];
    final playlist = await _get(
      'playlistItems',
      <String, String>{
        'part': 'snippet,contentDetails',
        'playlistId': uploads,
        'maxResults': '${maxResults.clamp(1, 50)}',
      },
      write: false,
    );
    final enriched = await _enrichViewCounts(YoutubeAccountResponseParser.playlistItemsToTracks(playlist));
    final musicOnly = enriched
        .where((video) => YoutubeSearchService.isMusicChannelUpload(
              video,
              channelTitle: channelTitle.isNotEmpty ? channelTitle : video.channelTitle,
              channelDescription: channelDescription,
            ))
        .toList(growable: false);
    // Judul yang tidak memuat #Shorts tetap bisa berupa video pendek. Cek
    // URL Shorts untuk upload channel, bukan hanya mengandalkan kata kunci.
    return YoutubeSearchService().removeShorts(musicOnly);
  }

  @override
  Future<List<YoutubeSearchResult>> likedVideos({int maxResults = 50}) async {
    final channelData = await _get(
      'channels',
      const <String, String>{'part': 'contentDetails', 'mine': 'true'},
      write: false,
    );
    final channels = channelData['items'];
    if (channels is! List || channels.isEmpty) return const [];
    final first = Map<String, dynamic>.from(channels.first as Map);
    final content = Map<String, dynamic>.from(first['contentDetails'] as Map? ?? const {});
    final related = Map<String, dynamic>.from(content['relatedPlaylists'] as Map? ?? const {});
    final likesId = related['likes']?.toString() ?? '';
    if (likesId.isEmpty) return const [];
    final data = await _get(
      'playlistItems',
      <String, String>{
        'part': 'snippet,contentDetails',
        'playlistId': likesId,
        'maxResults': '$maxResults',
      },
      write: false,
    );
    final enriched = await _enrichViewCounts(YoutubeAccountResponseParser.playlistItemsToTracks(data));
    final musicOnly = enriched
        .where((video) => YoutubeSearchService.isMusicCatalogItem(
              video,
              requireCategoryId: true,
            ))
        .toList(growable: false);
    return YoutubeSearchService().removeShorts(musicOnly);
  }

  @override
  Future<List<YoutubePlaylistSummary>> playlists({int maxResults = 50}) async {
    final data = await _get(
      'playlists',
      <String, String>{
        'part': 'snippet,contentDetails,status',
        'mine': 'true',
        'maxResults': '$maxResults',
      },
      write: false,
    );
    final items = data['items'];
    if (items is! List) return const [];
    return items.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
      final content = Map<String, dynamic>.from(map['contentDetails'] as Map? ?? const {});
      final status = Map<String, dynamic>.from(map['status'] as Map? ?? const {});
      return YoutubePlaylistSummary(
        id: map['id']?.toString() ?? '',
        title: snippet['title']?.toString() ?? 'Playlist',
        description: snippet['description']?.toString() ?? '',
        privacyStatus: status['privacyStatus']?.toString() ?? 'private',
        itemCount: (content['itemCount'] as num?)?.toInt() ?? 0,
        thumbnailUrl: YoutubeAccountResponseParser.thumbnail(snippet['thumbnails']),
      );
    }).where((item) => item.id.isNotEmpty).toList(growable: false);
  }

  /// Satu halaman item playlist TANPA statistik (murah: 1 unit kuota).
  /// Dipakai untuk menelusuri seluruh upload channel saat diurutkan terlama.
  Future<({List<YoutubeSearchResult> items, String? nextPageToken})> playlistItemsPage(
    String playlistId, {
    String? pageToken,
    int maxResults = 50,
    bool forceRefresh = false,
  }) async {
    final cacheScope = _user?.id ?? _user?.email ?? 'public';
    final rawCacheKey = '$cacheScope|$playlistId|${pageToken ?? 'first'}|$maxResults';
    final cacheKey = 'upload:${crypto.sha256.convert(utf8.encode(rawCacheKey))}';
    if (!forceRefresh) {
      final cached = await _uploadPageCache.get(
        cacheKey,
        maxAge: const Duration(hours: 2),
      );
      if (cached is Map && cached['items'] is List) {
        final rawItems = cached['items'] as List;
        final items = rawItems
            .whereType<Map>()
            .map((item) => YoutubeSearchResult.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.videoId.isNotEmpty)
            .toList(growable: false);
        final rawToken = cached['nextPageToken']?.toString();
        return (
          items: items,
          nextPageToken: (rawToken == null || rawToken.isEmpty) ? null : rawToken,
        );
      }
    }

    final data = await _get(
      'playlistItems',
      <String, String>{
        'part': 'snippet,contentDetails',
        'playlistId': playlistId,
        'maxResults': '$maxResults',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      },
      write: false,
    );
    final token = data['nextPageToken']?.toString();
    final result = (
      items: YoutubeAccountResponseParser.playlistItemsToTracks(data),
      nextPageToken: (token == null || token.isEmpty) ? null : token,
    );
    await _uploadPageCache.put(cacheKey, <String, dynamic>{
      'items': result.items.map((item) => item.toJson()).toList(growable: false),
      'nextPageToken': result.nextPageToken,
    });
    return result;
  }

  /// Tambahkan jumlah penonton ke daftar video (maks. 50 per panggilan).
  Future<List<YoutubeSearchResult>> withViewCounts(List<YoutubeSearchResult> source) async {
    final out = <YoutubeSearchResult>[];
    for (var i = 0; i < source.length; i += 50) {
      final end = (i + 50 < source.length) ? i + 50 : source.length;
      out.addAll(await _enrichViewCounts(source.sublist(i, end)));
    }
    return out;
  }

  @override
  Future<List<YoutubeSearchResult>> playlistItems(String playlistId, {int maxResults = 50}) async {
    final data = await _get(
      'playlistItems',
      <String, String>{
        'part': 'snippet,contentDetails',
        'playlistId': playlistId,
        'maxResults': '$maxResults',
      },
      write: false,
    );
    final enriched = await _enrichViewCounts(YoutubeAccountResponseParser.playlistItemsToTracks(data));
    final musicOnly = enriched
        .where((video) => YoutubeSearchService.isMusicCatalogItem(
              video,
              requireCategoryId: true,
            ))
        .toList(growable: false);
    return YoutubeSearchService().removeShorts(musicOnly);
  }

  Future<String> createPlaylist(
    String title, {
    String description = '',
    String privacyStatus = 'private',
  }) async {
    final data = await _post(
      'playlists',
      <String, dynamic>{
        'part': 'snippet,status',
        'snippet': {'title': title, 'description': description},
        'status': {'privacyStatus': privacyStatus},
      },
      write: true,
    );
    return data['id']?.toString() ?? '';
  }

  Future<void> addToPlaylist(String playlistId, String videoId) async {
    await _post(
      'playlistItems',
      <String, dynamic>{
        'part': 'snippet',
        'snippet': {
          'playlistId': playlistId,
          'resourceId': {'kind': 'youtube#video', 'videoId': videoId},
        },
      },
      write: true,
    );
  }

  Future<void> removeFromPlaylist(String playlistItemId) async {
    await _delete('playlistItems', <String, String>{'id': playlistItemId}, write: true);
  }


  Future<void> rateVideo(String videoId, String rating) async {
    final safe = rating == 'dislike' ? 'dislike' : 'like';
    await _post('videos/rate?id=${Uri.encodeQueryComponent(videoId)}&rating=$safe', <String, dynamic>{}, write: true);
  }

  Future<void> subscribe(String channelId) async {
    // `part` WAJIB berupa query parameter, bukan isi body.
    await _post(
      'subscriptions?part=snippet',
      <String, dynamic>{
        'snippet': {
          'resourceId': {'kind': 'youtube#channel', 'channelId': channelId},
        },
      },
      write: true,
    );
  }

  /// ID subscription milik user untuk [channelId], atau null kalau belum subscribe.
  Future<String?> subscriptionIdFor(String channelId) async {
    final data = await _get(
      'subscriptions',
      <String, String>{
        'part': 'id',
        'mine': 'true',
        'forChannelId': channelId,
      },
      write: false,
    );
    final items = data['items'];
    if (items is! List || items.isEmpty) return null;
    final id = (items.first as Map)['id']?.toString() ?? '';
    return id.isEmpty ? null : id;
  }

  Future<void> unsubscribe(String subscriptionId) async {
    await _delete('subscriptions', <String, String>{'id': subscriptionId}, write: true);
  }

  Future<YoutubeChannelDetails?> channelDetails(String channelId) async {
    final data = await _get(
      'channels',
      <String, String>{
        'part': 'snippet,contentDetails,statistics,brandingSettings',
        'id': channelId,
      },
      write: false,
    );
    final items = data['items'];
    if (items is! List || items.isEmpty) return null;
    final map = Map<String, dynamic>.from(items.first as Map);
    final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
    final content = Map<String, dynamic>.from(map['contentDetails'] as Map? ?? const {});
    final stats = Map<String, dynamic>.from(map['statistics'] as Map? ?? const {});
    final branding = Map<String, dynamic>.from(map['brandingSettings'] as Map? ?? const {});
    final image = Map<String, dynamic>.from(branding['image'] as Map? ?? const {});
    final related = Map<String, dynamic>.from(content['relatedPlaylists'] as Map? ?? const {});
    return YoutubeChannelDetails(
      id: map['id']?.toString() ?? channelId,
      title: snippet['title']?.toString() ?? 'Channel',
      handle: snippet['customUrl']?.toString() ?? '',
      description: snippet['description']?.toString() ?? '',
      avatarUrl: YoutubeAccountResponseParser.thumbnail(snippet['thumbnails']),
      bannerUrl: image['bannerExternalUrl']?.toString() ?? '',
      subscriberCount: int.tryParse(stats['subscriberCount']?.toString() ?? ''),
      hiddenSubscriberCount: stats['hiddenSubscriberCount'] == true,
      videoCount: int.tryParse(stats['videoCount']?.toString() ?? ''),
      uploadsPlaylistId: related['uploads']?.toString() ?? '',
    );
  }

  Future<Map<String, dynamic>> currentChannel() async {
    final data = await _get(
      'channels',
      const <String, String>{'part': 'snippet,contentDetails,statistics', 'mine': 'true'},
      write: false,
    );
    final items = data['items'];
    if (items is List && items.isNotEmpty) return Map<String, dynamic>.from(items.first as Map);
    return const {};
  }

  Future<List<YoutubeSearchResult>> _enrichViewCounts(
    List<YoutubeSearchResult> source,
  ) async {
    if (source.isEmpty) return source;

    final detailsById = <String, YoutubeSearchResult>{};
    // videos.list accepts up to 50 IDs per call. Cache each batch in one local
    // write instead of performing hundreds of small SharedPreferences writes.
    for (var i = 0; i < source.length; i += 50) {
      final end = (i + 50 < source.length) ? i + 50 : source.length;
      final chunk = source.sublist(i, end);
      final sortedIds = chunk.map((e) => e.videoId).toList()..sort();
      final batchKey = 'ids:${crypto.sha256.convert(utf8.encode(sortedIds.join(',')))}';
      final cached = await _enrichedVideoCache.get(
        batchKey,
        maxAge: const Duration(hours: 6),
      );
      if (cached is List) {
        for (final item in cached) {
          if (item is! Map) continue;
          try {
            final detail = YoutubeSearchResult.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (detail.videoId.isNotEmpty) detailsById[detail.videoId] = detail;
          } catch (_) {}
        }
        if (cached.isNotEmpty || chunk.isEmpty) continue;
      }

      final data = await _get(
        'videos',
        <String, String>{
          'part': 'snippet,statistics,contentDetails,liveStreamingDetails',
          'id': chunk.map((e) => e.videoId).join(','),
        },
        write: false,
      );
      final items = data['items'];
      if (items is! List) continue;
      final batchDetails = <YoutubeSearchResult>[];
      for (final item in items) {
        if (item is! Map) continue;
        final detail = YoutubeSearchResult.fromVideoResource(
          Map<String, dynamic>.from(item),
        );
        if (detail == null || detail.videoId.isEmpty) continue;
        detailsById[detail.videoId] = detail;
        batchDetails.add(detail);
      }
      if (batchDetails.isNotEmpty) {
        await _enrichedVideoCache.put(
          batchKey,
          batchDetails.map((detail) => detail.toJson()).toList(growable: false),
        );
      }
    }

    return source.map((video) {
      final detail = detailsById[video.videoId];
      if (detail == null) return video;
      return video.copyWith(
        viewCount: detail.viewCount ?? video.viewCount,
        durationSeconds: detail.durationSeconds ?? video.durationSeconds,
        liveStatus: detail.liveStatus.isNotEmpty ? detail.liveStatus : video.liveStatus,
        concurrentViewers: detail.concurrentViewers ?? video.concurrentViewers,
        liveStartTime: detail.liveStartTime ?? video.liveStartTime,
        channelId: detail.channelId.isNotEmpty ? detail.channelId : video.channelId,
        categoryId: detail.categoryId.isNotEmpty ? detail.categoryId : video.categoryId,
        description: detail.description.isNotEmpty ? detail.description : video.description,
      );
    }).toList(growable: false);
  }

  /// Video terbaru dari banyak channel sekaligus (paralel) lewat playlist
  /// upload-nya, lengkap dengan status live. Hemat kuota: 1 unit per channel
  /// + 1 unit per 50 video.
  @override
  Future<List<YoutubeSearchResult>> subscriptionFeed(
    List<YoutubeChannelSummary> channels, {
    int channelLimit = 200,
    int perChannel = 5,
  }) async {
    // subscriptions() resolves at most 200 channels (4 pages x 50). Inspect
    // that same set here instead of silently limiting the music feed to 20.
    final targets = channels
        .where((c) => c.uploadsPlaylistId.isNotEmpty)
        .take(channelLimit.clamp(1, 200).toInt())
        .toList(growable: false);
    if (targets.isEmpty) return const [];

    // Keep concurrency low. Per-channel upload pages are cached for two hours,
    // so reopening the subscription feed does not hit every channel again.
    final lists = <List<YoutubeSearchResult>>[];
    const batchSize = 4;
    for (var start = 0; start < targets.length; start += batchSize) {
      final end = (start + batchSize < targets.length) ? start + batchSize : targets.length;
      final batch = targets.sublist(start, end);
      final batchLists = await Future.wait(batch.map((c) async {
        try {
          final page = await playlistItemsPage(
            c.uploadsPlaylistId,
            maxResults: perChannel.clamp(1, 50).toInt(),
          );
          // Some playlistItems payloads omit videoOwnerChannelId. Preserve the
          // owning subscription's identity so channel-profile music signals
          // can still be applied to covers and independent uploads.
          return page.items.map((video) {
            if (video.channelId.isNotEmpty) return video;
            return video.copyWith(
              channelId: c.id,
              channelTitle: video.channelTitle.trim().isEmpty ||
                      video.channelTitle == 'Channel'
                  ? c.title
                  : video.channelTitle,
            );
          }).toList(growable: false);
        } catch (_) {
          return const <YoutubeSearchResult>[];
        }
      }));
      lists.addAll(batchLists);
    }

    final seen = <String>{};
    final all = <YoutubeSearchResult>[
      for (final list in lists)
        for (final video in list)
          if (seen.add(video.videoId)) video,
    ];
    if (all.isEmpty) return const [];

    List<YoutubeSearchResult> enriched;
    try {
      enriched = await withViewCounts(all);
    } catch (_) {
      enriched = all;
    }
    final channelById = <String, YoutubeChannelSummary>{
      for (final channel in targets) channel.id: channel,
    };
    enriched = enriched.where((video) {
      final channel = channelById[video.channelId];
      return YoutubeSearchService.isMusicChannelUpload(
        video,
        channelTitle: channel?.title ?? video.channelTitle,
        channelDescription: channel?.description ?? '',
      );
    }).toList(growable: false);
    // Subscription feed used to stop at title/category heuristics, so unnamed
    // Shorts from subscribed channels leaked into Home and Langganan. Verify
    // the remaining candidates in bounded concurrent batches before sorting.
    enriched = await YoutubeSearchService().removeShorts(enriched);
    enriched.sort((a, b) {
      // Yang sedang live selalu di atas, sisanya terbaru dulu.
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      return (b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
    });
    return enriched;
  }

  /// Menelusuri upload channel untuk menemukan siaran langsung: yang sedang
  /// live, yang dijadwalkan, dan rekaman live yang sudah selesai. Murah:
  /// sekitar 2 unit kuota per 50 upload. Lanjutkan dengan [pageToken].
  Future<({List<YoutubeSearchResult> items, String? nextPageToken})> scanLiveVideos(
    String uploadsPlaylistId, {
    String? pageToken,
    int maxPages = 4,
    String channelTitle = '',
    String channelDescription = '',
  }) async {
    final found = <YoutubeSearchResult>[];
    String? token = pageToken;
    var pages = 0;
    do {
      final page = await playlistItemsPage(uploadsPlaylistId, pageToken: token);
      token = page.nextPageToken;
      pages++;
      if (page.items.isNotEmpty) {
        final detailed = await _enrichViewCounts(page.items);
        final musicOnly = detailed.where((video) =>
            video.liveStatus.isNotEmpty &&
            YoutubeSearchService.isMusicChannelUpload(
              video,
              channelTitle: channelTitle.isNotEmpty ? channelTitle : video.channelTitle,
              channelDescription: channelDescription,
            )).toList(growable: false);
        found.addAll(await YoutubeSearchService().removeShorts(musicOnly));
      }
    } while (token != null && pages < maxPages);
    return (items: found, nextPageToken: token);
  }

  Future<void> dispose() async {
    await _currentUserSubscription?.cancel();
    _currentUserSubscription = null;
  }
}
