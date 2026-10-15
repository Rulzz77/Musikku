import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/youtube_search_result.dart';

class YoutubeChannelSummary {
  final String id;
  final String title;
  final String description;
  final String thumbnailUrl;
  final String uploadsPlaylistId;
  final int? subscriberCount;

  const YoutubeChannelSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.uploadsPlaylistId,
    this.subscriberCount,
  });
}

class YoutubeChannelDetails {
  final String id;
  final String title;
  final String handle;
  final String description;
  final String avatarUrl;
  final String bannerUrl;
  final int? subscriberCount;
  final bool hiddenSubscriberCount;
  final int? videoCount;
  final String uploadsPlaylistId;

  const YoutubeChannelDetails({
    required this.id,
    required this.title,
    this.handle = '',
    this.description = '',
    this.avatarUrl = '',
    this.bannerUrl = '',
    this.subscriberCount,
    this.hiddenSubscriberCount = false,
    this.videoCount,
    this.uploadsPlaylistId = '',
  });
}

class YoutubePlaylistSummary {
  final String id;
  final String title;
  final String description;
  final String privacyStatus;
  final int itemCount;
  final String thumbnailUrl;

  const YoutubePlaylistSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.privacyStatus,
    required this.itemCount,
    this.thumbnailUrl = '',
  });
}

class YoutubeAccountService {
  static final YoutubeAccountService instance = YoutubeAccountService._();

  YoutubeAccountService._();

  static const _scopeReadonly = 'https://www.googleapis.com/auth/youtube.readonly';
  static const _scopeManage = 'https://www.googleapis.com/auth/youtube';
  static const _base = 'https://www.googleapis.com/youtube/v3';
  static const _sessionOkKey = 'youtube_session_ok';

  /// Dipakai untuk data publik (channel, video, playlist upload) saat pengguna
  /// belum login, jadi halaman channel bisa dibuka tanpa akun Google.
  static const String _apiKey = String.fromEnvironment('YOUTUBE_API_KEY');

  /// SEMUA scope diminta sekaligus dalam satu layar izin. Sebelumnya login
  /// meminta readonly, lalu tombol "Izinkan" meminta scope lain, sementara
  /// pemanggilan API memeriksa scope yang berbeda lagi, sehingga izin diminta
  /// berulang dan login terlihat gagal.
  static const _allScopes = <String>[_scopeReadonly, _scopeManage];

  final GoogleSignIn _signIn = GoogleSignIn.instance;
  GoogleSignInAccount? _user;
  bool _initialized = false;
  Future<void> _authorizationTail = Future<void>.value();
  Future<void> _sessionTail = Future<void>.value();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authEventsSubscription;
  bool _interactiveAuthorizationAllowed = false;
  bool _readonlyAuthorizationGranted = false;
  Completer<GoogleSignInAccount?>? _lightweightRestoreCompleter;

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
    await _signIn.initialize(serverClientId: serverClientId);

    _authEventsSubscription ??= _signIn.authenticationEvents.listen(
      (event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _user = event.user;
          // Restore event dapat datang setelah attemptLightweightAuthentication
          // selesai. Cek readonly authorization tanpa memunculkan UI.
          unawaited(_refreshRestoredAuthorization(event.user));
          // google_sign_in 7.x menganjurkan stream authenticationEvents sebagai
          // sumber kebenaran state sign-in. attemptLightweightAuthentication()
          // boleh mengembalikan null sementara event sign-in tetap dikirim.
          final completer = _lightweightRestoreCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete(event.user);
          }
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          _user = null;
          _readonlyAuthorizationGranted = false;
          unawaited(_clearRememberedUser());
        }
      },
      onError: (_) {},
    );

    _initialized = true;
  }

  Future<void> _refreshRestoredAuthorization(GoogleSignInAccount account) async {
    try {
      final authorization = await account.authorizationClient.authorizationForScopes(<String>[_scopeReadonly]);
      if (identical(_user, account)) {
        _readonlyAuthorizationGranted = authorization != null;
      }
    } catch (_) {
      // Jangan tampilkan UI di background. Fitur yang butuh authorization
      // interaktif akan memintanya saat user menekan aksinya.
    }
  }

  Future<GoogleSignInAccount> signIn() async {
    return _serializeSession(() async {
      await _ensureInitialized();
      if (!_signIn.supportsAuthenticate()) {
        throw StateError('Google Sign-In tidak tersedia pada platform ini.');
      }

      // Authentication dan authorization dipisahkan. Berhasil memilih akun
      // Google harus tetap dianggap login, meskipun scope YouTube belum bisa
      // diberikan pada saat yang sama. Kalau consent gagal/dibatalkan, user
      // tidak dikeluarkan lagi sehingga tidak masuk loop login setiap buka app.
      final account = await _signIn.authenticate();
      _user = account;
      await _rememberUser(account);
      await _setSessionOk(true);

      _interactiveAuthorizationAllowed = true;
      try {
        await _authorize(<String>[_scopeReadonly]);
        _readonlyAuthorizationGranted = true;
      } catch (e) {
        _readonlyAuthorizationGranted = false;
        // Jangan signOut. UI akan menampilkan tombol "Izinkan" dan hanya
        // meminta consent ketika user benar-benar memakai fitur akun.
        // Authentication Google sendiri sudah sukses.
      } finally {
        _interactiveAuthorizationAllowed = false;
      }

      return account;
    });
  }

  /// Memulihkan sesi login TANPA menampilkan popup apa pun.
  ///
  /// Jangan bergantung pada nilai Future dari attemptLightweightAuthentication()
  /// saja: pada google_sign_in 7.x, state yang benar harus diambil dari
  /// authenticationEvents, dan Future-nya bisa bernilai null walaupun event
  /// sign-in tetap diterbitkan.
  Future<void> tryRestoreSession() async {
    await _serializeSession(() async {
      if (_user != null) return;
      final remembered = await hasRestorableSession();
      if (!remembered) return;
      await _ensureInitialized();

      final restoreCompleter = Completer<GoogleSignInAccount?>();
      _lightweightRestoreCompleter = restoreCompleter;
      try {
        GoogleSignInAccount? restored;
        try {
          restored = await _signIn.attemptLightweightAuthentication();
        } catch (_) {
          restored = null;
        }

        // Nilai Future boleh null walaupun authenticationEvents mengirim
        // event SignIn sesudahnya. Beri event stream kesempatan menyelesaikan
        // restore, tetapi jangan pernah menampilkan UI login otomatis.
        if (_user == null && restored == null) {
          try {
            _user = await restoreCompleter.future.timeout(
              const Duration(milliseconds: 1800),
            );
          } on TimeoutException {
            // Tidak ada akun yang bisa dipulihkan secara diam-diam.
          }
        } else if (_user == null && restored != null) {
          _user = restored;
        }

        if (_user != null) {
          await _rememberUser(_user!);
          await _setSessionOk(true);
          final authorization = await _user!.authorizationClient
              .authorizationForScopes(<String>[_scopeReadonly]);
          _readonlyAuthorizationGranted = authorization != null;
        }
      } finally {
        _lightweightRestoreCompleter = null;
      }
    });
  }

  /// true kalau sebelumnya login + izin YouTube sudah selesai dengan sukses,
  /// jadi aman dipulihkan diam-diam saat aplikasi dibuka.
  Future<bool> hasRestorableSession() async {
    final prefs = await SharedPreferences.getInstance();
    // Identitas akun yang pernah berhasil login cukup untuk mencoba
    // lightweight authentication lagi. Status scope boleh kadaluarsa/revoke
    // tanpa memaksa pengguna memilih akun Google dari awal.
    final email = prefs.getString('youtube_last_account_email') ?? '';
    return email.isNotEmpty;
  }

  Future<void> _setSessionOk(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sessionOkKey, value);
  }

  Future<void> signOut() async {
    await _serializeSession(() async {
      await _ensureInitialized();
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

  Future<GoogleSignInClientAuthorization> _authorize(List<String> scopes) {
    final previous = _authorizationTail;
    final done = Completer<void>();
    _authorizationTail = done.future;
    return () async {
      await previous;
      try {
        final account = _user;
        if (account == null) {
          throw StateError('Belum login ke Google.');
        }
        var authorization = await account.authorizationClient.authorizationForScopes(scopes);
        if (authorization == null) {
          if (!_interactiveAuthorizationAllowed) {
            throw StateError('YOUTUBE_AUTH_REQUIRED');
          }
          authorization = await account.authorizationClient.authorizeScopes(scopes);
        }
        return authorization;
      } finally {
        done.complete();
      }
    }();
  }

  Future<bool> authorizeYouTubeAccess() async {
    return _serializeSession(() async {
      await _ensureInitialized();
      if (_user == null) return false;
      _interactiveAuthorizationAllowed = true;
      try {
        await _authorize(_allScopes);
        _readonlyAuthorizationGranted = true;
        return true;
      } finally {
        _interactiveAuthorizationAllowed = false;
      }
    });
  }

  /// Dipanggil dari tap pengguna (mis. tombol Subscribe) saat butuh akun:
  /// pulihkan sesi lama kalau ada, kalau tidak tampilkan pemilih akun Google.
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
    if (_user == null) {
      throw StateError('Silakan login Google terlebih dahulu.');
    }
    final authorization = await _authorize(_allScopes);
    return authorization.accessToken;
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> params, {
    required bool write,
  }) async {
    // Endpoint milik akun (mine=true) wajib login. Selain itu datanya publik
    // dan boleh diambil dengan API key kalau belum login / izin belum siap.
    final isPrivate = params['mine'] == 'true';

    Future<Map<String, dynamic>> publicGet() async {
      final uri = Uri.parse('$_base/$path').replace(
        queryParameters: <String, String>{...params, 'key': _apiKey},
      );
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('YouTube API ${response.statusCode}: ${response.body}');
      }
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }

    if (!isPrivate && _apiKey.isNotEmpty && _user == null) {
      return publicGet();
    }

    final String token;
    try {
      token = await _accessToken(write: write);
    } catch (_) {
      if (!isPrivate && _apiKey.isNotEmpty) return publicGet();
      rethrow;
    }
    final uri = Uri.parse('$_base/$path').replace(queryParameters: params);
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('YouTube API ${response.statusCode}: ${response.body}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    required bool write,
  }) async {
    final token = await _accessToken(write: write);
    final response = await http.post(
      Uri.parse('$_base/$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('YouTube API ${response.statusCode}: ${response.body}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<void> _delete(
    String path,
    Map<String, String> params, {
    required bool write,
  }) async {
    final token = await _accessToken(write: write);
    final uri = Uri.parse('$_base/$path').replace(queryParameters: params);
    final response = await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('YouTube API ${response.statusCode}: ${response.body}');
    }
  }

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
          thumbnailUrl: _thumbnail(snippet['thumbnails']),
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
            thumbnailUrl: _thumbnail(snippet['thumbnails']).isNotEmpty
                ? _thumbnail(snippet['thumbnails'])
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
    final results = _playlistItemsToTracks(playlist);
    return _enrichViewCounts(results);
  }

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
    return _enrichViewCounts(_playlistItemsToTracks(data));
  }

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
        thumbnailUrl: _thumbnail(snippet['thumbnails']),
      );
    }).where((item) => item.id.isNotEmpty).toList(growable: false);
  }

  /// Satu halaman item playlist TANPA statistik (murah: 1 unit kuota).
  /// Dipakai untuk menelusuri seluruh upload channel saat diurutkan terlama.
  Future<({List<YoutubeSearchResult> items, String? nextPageToken})> playlistItemsPage(
    String playlistId, {
    String? pageToken,
    int maxResults = 50,
  }) async {
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
    return (
      items: _playlistItemsToTracks(data),
      nextPageToken: (token == null || token.isEmpty) ? null : token,
    );
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
    return _enrichViewCounts(_playlistItemsToTracks(data));
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
      avatarUrl: _thumbnail(snippet['thumbnails']),
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

  Future<List<YoutubeSearchResult>> _enrichViewCounts(List<YoutubeSearchResult> source) async {
    if (source.isEmpty) return source;
    final ids = source.map((e) => e.videoId).where((e) => e.isNotEmpty).toList();
    final data = await _get(
      'videos',
      <String, String>{
        'part': 'snippet,statistics,contentDetails,liveStreamingDetails',
        'id': ids.join(','),
      },
      write: false,
    );
    final details = <String, YoutubeSearchResult>{};
    final items = data['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final video = YoutubeSearchResult.fromVideoResource(Map<String, dynamic>.from(item));
        if (video != null) details[video.videoId] = video;
      }
    }
    return source.map((e) {
      final d = details[e.videoId];
      if (d == null) return e;
      return e.copyWith(
        viewCount: d.viewCount,
        durationSeconds: d.durationSeconds,
        liveStatus: d.liveStatus,
        concurrentViewers: d.concurrentViewers,
        liveStartTime: d.liveStartTime,
        channelId: d.channelId.isNotEmpty ? d.channelId : e.channelId,
      );
    }).toList(growable: false);
  }

  /// Video terbaru dari banyak channel sekaligus (paralel) lewat playlist
  /// upload-nya, lengkap dengan status live. Hemat kuota: 1 unit per channel
  /// + 1 unit per 50 video.
  Future<List<YoutubeSearchResult>> subscriptionFeed(
    List<YoutubeChannelSummary> channels, {
    int channelLimit = 20,
    int perChannel = 3,
  }) async {
    final targets = channels
        .where((c) => c.uploadsPlaylistId.isNotEmpty)
        .take(channelLimit)
        .toList(growable: false);
    if (targets.isEmpty) return const [];

    final lists = await Future.wait(targets.map((c) async {
      try {
        final page = await playlistItemsPage(c.uploadsPlaylistId, maxResults: perChannel);
        return page.items;
      } catch (_) {
        return const <YoutubeSearchResult>[];
      }
    }));

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
        found.addAll(detailed.where((v) => v.liveStatus.isNotEmpty));
      }
    } while (token != null && pages < maxPages);
    return (items: found, nextPageToken: token);
  }

  List<YoutubeSearchResult> _playlistItemsToTracks(Map<String, dynamic> data) {
    final items = data['items'];
    if (items is! List) return const [];
    return items.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
      final content = Map<String, dynamic>.from(map['contentDetails'] as Map? ?? const {});
      final videoId = content['videoId']?.toString() ?? '';
      return YoutubeSearchResult(
        videoId: videoId,
        title: snippet['title']?.toString() ?? 'Tanpa judul',
        channelTitle: snippet['videoOwnerChannelTitle']?.toString() ??
            snippet['channelTitle']?.toString() ??
            'Channel',
        thumbnailUrl: _thumbnail(snippet['thumbnails']),
        publishedAt: DateTime.tryParse(snippet['publishedAt']?.toString() ?? ''),
        channelId: snippet['videoOwnerChannelId']?.toString() ?? '',
      );
    }).where((item) => item.videoId.isNotEmpty).toList(growable: false);
  }

  String _thumbnail(dynamic raw) {
    if (raw is! Map) return '';
    for (final key in const ['maxres', 'high', 'standard', 'medium', 'default']) {
      final item = raw[key];
      if (item is Map) {
        final url = item['url']?.toString() ?? '';
        if (url.isNotEmpty) return url;
      }
    }
    return '';
  }
  Future<void> dispose() async {
    await _authEventsSubscription?.cancel();
    _authEventsSubscription = null;
  }
}

/// Mengubah error login/izin menjadi pesan yang bisa ditindaklanjuti.
String describeLoginError(Object e) {
  if (e is StateError) {
    if (e.message == 'YOUTUBE_AUTH_REQUIRED') {
      return 'Izin YouTube belum disetujui. Tekan "Izinkan" atau login ulang.';
    }
    return e.message;
  }
  if (e is GoogleSignInException) {
    final code = e.code.name;
    final detail = (e.description ?? '').trim();
    if (code == 'canceled') {
      return 'Login dibatalkan atau ditolak Google. Kalau kamu tidak '
          'membatalkannya, biasanya konfigurasi OAuth belum cocok: cek SHA-1 '
          'dan package com.musikku.app di Google Cloud, Web Client ID, dan '
          'pastikan akunmu terdaftar sebagai test user.'
          '${detail.isEmpty ? '' : ' ($detail)'}';
    }
    if (code == 'clientConfigurationError' || code == 'providerConfigurationError') {
      return 'Konfigurasi Google Sign-In salah ($code). Cek SHA-1, package '
          'com.musikku.app, dan Web Client ID.${detail.isEmpty ? '' : ' ($detail)'}';
    }
    return 'Login gagal ($code).${detail.isEmpty ? '' : ' $detail'}';
  }
  final text = e.toString();
  return 'Gagal: ${text.length > 180 ? '${text.substring(0, 180)}…' : text}';
}
