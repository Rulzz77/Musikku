import 'dart:async';

import 'package:flutter/material.dart';

import '../models/youtube_channel_models.dart';
import '../models/youtube_search_result.dart';
import '../services/youtube_public_channel_service.dart';
import '../services/youtube_search_service.dart';
import '../widgets/unified_artwork.dart';
import '../widgets/music_design.dart';

/// Profil artis dengan banner, kontrol putar artis, dan katalog lagu resmi.
/// Halaman ini tidak memuat playlist publik agar profil artis tetap fokus
/// pada lagu-lagu milik artis dan tidak menghabiskan request playlist API.
class ArtistPage extends StatefulWidget {
  const ArtistPage({
    super.key,
    required this.artist,
    required this.searchService,
    required this.onPlay,
    this.channelId = '',
    this.initialSearchResults = const [],
    this.onLongPress,
    this.onPlayList,
  });

  final String artist;
  final String channelId;
  final List<YoutubeSearchResult> initialSearchResults;
  final YoutubeSearchService searchService;
  final ValueChanged<YoutubeSearchResult> onPlay;
  final ValueChanged<YoutubeSearchResult>? onLongPress;

  /// Dipakai agar Next mengikuti urutan lagu artis, bukan Radio.
  final Future<void> Function(
    YoutubeSearchResult selected,
    List<YoutubeSearchResult> tracks,
  )? onPlayList;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  final YoutubePublicChannelService _channelService =
      YoutubePublicChannelService.instance;

  YoutubeChannelDetails? _details;
  List<YoutubeSearchResult> _songs = const [];
  String _uploadsPlaylistId = '';
  String? _nextSongsToken;
  bool _loading = true;
  bool _loadingMoreSongs = false;
  Object? _error;
  bool _usedSearchFallback = false;

  String get _artistTitle => _details?.title.isNotEmpty == true
      ? _details!.title
      : widget.artist;

  String get _artistImageUrl {
    final banner = _details?.bannerUrl.trim() ?? '';
    if (banner.isNotEmpty) return banner;
    return _details?.avatarUrl.trim() ?? '';
  }

  static final RegExp _nonMusicContentTitle = RegExp(
    r'\b(?:vlogs?|daily\s+vlog|podcasts?|interviews?|wawancara|reaction(?:s)?|reacts?\s+to|reviews?|tutorials?|how\s+to|behind\s+the\s+scenes|making\s+of|studio\s+tour|day\s+in\s+the\s+life|daily\s+life|life\s+update|career\s+update|channel\s+update|tour\s+diary|travel\s+(?:vlog|diary)|road\s+trip|gaming|gameplay|lets?\s+play|challenges?|unboxing|q\s*&\s*a|questions?\s+and\s+answers?|news\s+(?:update|report)|breaking\s+news|announcements?|pranks?|comedy|funny\s+moments?|shorts?|skits?|documentar(?:y|ies)|meet\s+and\s+greet|press\s+conference|livestreams?)\b',
    caseSensitive: false,
  );

  static final RegExp _unofficialContent = RegExp(
    r'\b(?:cover(?:ed)?|karaoke|fan[ -]?made|unofficial|reaction|reacts?|tribute|slowed|sped\s*up|nightcore|dance\s+practice|teasers?|trailers?|snippets?)\b',
    caseSensitive: false,
  );

  bool _isClearlyNonMusic(YoutubeSearchResult video) =>
      _nonMusicContentTitle.hasMatch(video.title);

  bool _hasSongLikeDuration(YoutubeSearchResult video) {
    final seconds = video.durationSeconds;
    return seconds == null || (seconds >= 45 && seconds <= 900);
  }

  String _normalizeArtistText(String value) => value
      .toLowerCase()
      .replaceAll(
        RegExp(
          r'\b(?:official(?:\s+music)?(?:\s+channel)?|vevo|topic|music\s+channel|channel)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _containsArtistPhrase(String text, String artist) =>
      text == artist ||
      text.startsWith('$artist ') ||
      text.endsWith(' $artist') ||
      text.contains(' $artist ');

  /// Ambil lagu yang memang cocok dengan artis ini. Cover, karaoke, fan edit,
  /// reaction, dan konten nonmusik tidak dimasukkan ke katalog artis.
  List<YoutubeSearchResult> _filterArtistSearchResults(
    List<YoutubeSearchResult> source,
  ) {
    final artist = _normalizeArtistText(widget.artist);
    if (artist.isEmpty) return const [];

    final seen = <String>{};
    final tracks = <YoutubeSearchResult>[];
    final officialPattern = RegExp(
      r'\b(?:official|vevo|topic|official\s+audio|official\s+(?:music\s+)?video|official\s+lyrics?|official\s+visualizer|visualizer|records?|recordings?|label|entertainment|production|productions|music|musik|vibe)\b',
      caseSensitive: false,
    );

    for (final video in source) {
      if (video.videoId.isEmpty ||
          video.isLocal ||
          video.isLive ||
          video.isUpcoming ||
          _isClearlyNonMusic(video) ||
          !seen.add(video.videoId)) {
        continue;
      }

      final title = _normalizeArtistText(video.title);
      final channel = _normalizeArtistText(video.channelTitle);
      final artistInTitle = _containsArtistPhrase(title, artist);
      final artistChannel = _containsArtistPhrase(channel, artist) ||
          _containsArtistPhrase(artist, channel);
      if (!artistInTitle && !artistChannel) continue;

      final rawMetadata =
          '${video.title} ${video.description} ${video.channelTitle}';
      if (_unofficialContent.hasMatch(rawMetadata)) continue;
      if (!artistChannel && !officialPattern.hasMatch(rawMetadata)) continue;
      if (!YoutubeSearchService.isMusicChannelUpload(
        video,
        channelTitle: video.channelTitle,
      )) {
        continue;
      }
      tracks.add(video);
    }

    return tracks.take(50).toList(growable: false);
  }

  List<YoutubeSearchResult> _mergeTracks(
    List<YoutubeSearchResult> primary,
    List<YoutubeSearchResult> secondary,
  ) {
    final seen = <String>{};
    final merged = <YoutubeSearchResult>[];
    for (final track in [...primary, ...secondary]) {
      if (track.videoId.isNotEmpty && seen.add(track.videoId)) {
        merged.add(track);
      }
    }
    return merged;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _songs = _filterArtistSearchResults(widget.initialSearchResults);

    try {
      final channelId = widget.channelId.trim();
      if (channelId.isNotEmpty) {
        try {
          final details = await _channelService.channelDetails(channelId);
          if (!mounted) return;
          _details = details;
          _uploadsPlaylistId = details?.uploadsPlaylistId ?? '';

          final uploadId = _uploadsPlaylistId;
          final title = details?.title.isNotEmpty == true
              ? details!.title
              : widget.artist;
          final description = details?.description ?? '';

          if (uploadId.isNotEmpty) {
            try {
              final uploads = await _channelService.playlistItemsPage(
                uploadId,
                maxResults: 50,
              );
              final songs = await _filterChannelSongs(
                uploads.items,
                channelTitle: title,
                channelDescription: description,
              );
              if (!mounted) return;
              _songs = _mergeTracks(songs, _songs);
              _nextSongsToken = uploads.nextPageToken;
            } catch (_) {
              // Tetap gunakan hasil pencarian awal bila unggahan channel gagal.
            }
          }
        } catch (_) {
          // Sebagian channel ID dari cache lama mungkin sudah tidak tersedia.
        }
      }

      // Fallback hanya saat katalog dari channel dan hasil awal sama-sama kosong.
      if (_songs.isEmpty) {
        _usedSearchFallback = true;
        final searchResults = await widget.searchService.search(
          '${widget.artist} songs',
        );
        List<YoutubeSearchResult> enrichedResults;
        try {
          enrichedResults = await _channelService.withViewCounts(searchResults);
        } catch (_) {
          enrichedResults = searchResults;
        }
        final musicResults = enrichedResults
            .where(
              (video) =>
                  video.videoId.isNotEmpty &&
                  !video.isLocal &&
                  !video.isLive &&
                  !video.isUpcoming &&
                  !_isClearlyNonMusic(video) &&
                  YoutubeSearchService.isMusicChannelUpload(
                    video,
                    channelTitle: video.channelTitle,
                  ),
            )
            .toList(growable: false);
        final cleanResults = await widget.searchService.removeShorts(
          musicResults,
        );
        _songs = _mergeTracks(_filterArtistSearchResults(cleanResults), _songs);
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<List<YoutubeSearchResult>> _filterChannelSongs(
    List<YoutubeSearchResult> source, {
    required String channelTitle,
    required String channelDescription,
  }) async {
    List<YoutubeSearchResult> enriched;
    try {
      enriched = await _channelService.withViewCounts(source);
    } catch (_) {
      enriched = source;
    }

    final tracks = enriched
        .where(
          (video) =>
              video.videoId.isNotEmpty &&
              !video.isLocal &&
              !video.isLive &&
              !video.isUpcoming &&
              !_isClearlyNonMusic(video) &&
              !_unofficialContent.hasMatch(video.title) &&
              _hasSongLikeDuration(video) &&
              YoutubeSearchService.isMusicChannelUpload(
                video,
                channelTitle: channelTitle,
                channelDescription: channelDescription,
              ),
        )
        .toList(growable: false);
    return widget.searchService.removeShorts(tracks);
  }

  Future<void> _loadMoreSongs() async {
    final token = _nextSongsToken;
    if (_loadingMoreSongs || token == null || _uploadsPlaylistId.isEmpty) {
      return;
    }

    setState(() => _loadingMoreSongs = true);
    try {
      final page = await _channelService.playlistItemsPage(
        _uploadsPlaylistId,
        pageToken: token,
        maxResults: 50,
      );
      final filtered = await _filterChannelSongs(
        page.items,
        channelTitle: _artistTitle,
        channelDescription: _details?.description ?? '',
      );
      if (!mounted) return;
      final known = _songs.map((song) => song.videoId).toSet();
      setState(() {
        _songs = [
          ..._songs,
          ...filtered.where((song) => !known.contains(song.videoId)),
        ];
        _nextSongsToken = page.nextPageToken;
      });
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _loadingMoreSongs = false);
    }
  }

  void _showError(Object error) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _playTracks(
    YoutubeSearchResult selected,
    List<YoutubeSearchResult> tracks,
  ) async {
    final valid = tracks
        .where((track) => track.videoId.isNotEmpty && !track.isLocal)
        .toList(growable: false);
    if (valid.isEmpty) return;

    if (widget.onPlayList != null) {
      await widget.onPlayList!(selected, valid);
    } else {
      widget.onPlay(selected);
    }
  }

  Future<void> _playArtist({bool shuffle = false}) async {
    final tracks = _songs
        .where((track) => track.videoId.isNotEmpty && !track.isLocal)
        .toList();
    if (tracks.isEmpty) return;
    if (shuffle) tracks.shuffle();
    await _playTracks(tracks.first, tracks);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artis'),
        centerTitle: false,
      ),
      body: MusicBackdrop(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _songs.isEmpty
                ? _ErrorState(message: _error.toString(), onRetry: _load)
                : MusicPageEntrance(
                    child: Column(
                      children: [
                        _header(scheme),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Expanded(
                                child: Text(
                                  'Lagu populer',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ),
                              Text(
                                '${_songs.length} lagu',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _buildSongList()),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final imageUrl = _artistImageUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: SizedBox(
              height: 224,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl.isNotEmpty)
                    Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => _artistPlaceholder(scheme))
                  else
                    _artistPlaceholder(scheme),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x12000000), Color(0x18000000), Color(0xE8000000)],
                        stops: [0, 0.36, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 17,
                    right: 17,
                    bottom: 17,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(7)),
                          child: Text('PROFIL ARTIS', style: TextStyle(color: scheme.onPrimary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                        ),
                        const SizedBox(height: 9),
                        Text(_artistTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 30, height: 1.0, fontWeight: FontWeight.w900, letterSpacing: -1)),
                        const SizedBox(height: 5),
                        Text('${_songs.length} lagu dalam katalog', style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _songs.isEmpty ? null : () => unawaited(_playArtist()),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  icon: const Icon(Icons.play_arrow_rounded, size: 21),
                  label: const Text('Putar semua'),
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 52,
                height: 48,
                child: OutlinedButton(
                  onPressed: _songs.isEmpty ? null : () => unawaited(_playArtist(shuffle: true)),
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), side: BorderSide(color: scheme.outlineVariant)),
                  child: const Icon(Icons.shuffle_rounded, size: 19),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _artistPlaceholder(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              right: -28,
              top: -42,
              child: Icon(Icons.album_rounded, size: 220, color: scheme.primary.withValues(alpha: 0.12)),
            ),
            Icon(Icons.graphic_eq_rounded, size: 66, color: scheme.onPrimaryContainer.withValues(alpha: 0.78)),
          ],
        ),
      );

  Widget _buildSongList() {
    if (_songs.isEmpty) {
      return _EmptyState(
        icon: Icons.music_off_rounded,
        title: 'Lagu artis belum ditemukan',
        subtitle: _nextSongsToken != null && _uploadsPlaylistId.isNotEmpty
            ? 'Unggahan terbaru belum berisi lagu yang cocok. Muat unggahan berikutnya untuk mencari rilisan resmi.'
            : 'Belum ada lagu resmi yang dikenali untuk artis ini. Coba buka profil dari hasil pencarian lagu atau channel musik.',
        actionLabel: _nextSongsToken != null && _uploadsPlaylistId.isNotEmpty
            ? 'Muat lagu lainnya'
            : null,
        onAction: _nextSongsToken != null && _uploadsPlaylistId.isNotEmpty
            ? _loadMoreSongs
            : null,
        actionLoading: _loadingMoreSongs,
      );
    }

    final hasMore = _nextSongsToken != null && !_usedSearchFallback;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      itemCount: _songs.length + (hasMore || _loadingMoreSongs ? 1 : 0),
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 72,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.28),
      ),
      itemBuilder: (context, index) {
        if (index >= _songs.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: OutlinedButton.icon(
                onPressed: _loadingMoreSongs ? null : _loadMoreSongs,
                icon: _loadingMoreSongs
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(
                  _loadingMoreSongs ? 'Memuat...' : 'Muat lagu lainnya',
                ),
              ),
            ),
          );
        }

        final song = _songs[index];
        return _ArtistSongTile(
          video: song,
          artist: _artistTitle,
          onTap: () => unawaited(_playTracks(song, _songs)),
          onMore: widget.onLongPress == null
              ? null
              : () => widget.onLongPress!(song),
        );
      },
    );
  }
}

class _ArtistSongTile extends StatelessWidget {
  const _ArtistSongTile({
    required this.video,
    required this.artist,
    required this.onTap,
    this.onMore,
  });

  final YoutubeSearchResult video;
  final String artist;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: UnifiedArtwork(
                  track: video,
                  width: 58,
                  height: 58,
                  cacheWidth: 220,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (onMore != null)
                IconButton(
                  tooltip: 'Opsi lagu',
                  onPressed: onMore,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: scheme.onSurfaceVariant,
                    size: 21,
                  ),
                )
              else
                Icon(
                  Icons.play_circle_outline_rounded,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                  size: 23,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionLoading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: actionLoading ? null : onAction,
                icon: actionLoading
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(actionLoading ? 'Memuat...' : actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded, size: 60, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
