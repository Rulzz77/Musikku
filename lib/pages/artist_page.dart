import 'dart:async';

import 'package:flutter/material.dart';

import '../models/youtube_channel_models.dart';
import '../models/youtube_search_result.dart';
import '../services/youtube_public_channel_service.dart';
import '../services/youtube_search_service.dart';
import '../theme/app_colors.dart';
import '../widgets/unified_artwork.dart';

/// Halaman artis/channel dengan daftar lagu dan playlist publik dari channel.
/// Kalau channelId tidak tersedia, halaman memakai pencarian musik sebagai fallback.
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

  /// Dipakai agar Next mengikuti urutan lagu di channel/album, bukan Radio.
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
  List<YoutubePublicPlaylist> _playlists = const [];
  String _uploadsPlaylistId = '';
  String? _nextSongsToken;
  String? _nextPlaylistsToken;
  bool _loading = true;
  bool _loadingMoreSongs = false;
  bool _loadingMorePlaylists = false;
  Object? _error;
  int _tab = 0;
  bool _usedSearchFallback = false;

  String get _artistTitle => _details?.title.isNotEmpty == true
      ? _details!.title
      : widget.artist;

  // A channel can publish vlogs, interviews, podcasts, and music on the same
  // account. Artist pages should expose music releases only, not every public
  // playlist. Filter unambiguously non-music playlist names; generic album
  // names are kept because many albums are named only after the record title.
  static final RegExp _nonMusicContentTitle = RegExp(
    r'\b(?:vlogs?|daily\s+vlog|podcasts?|interviews?|wawancara|reaction(?:s)?|reacts?\s+to|reviews?|tutorials?|how\s+to|behind\s+the\s+scenes|making\s+of|studio\s+tour|day\s+in\s+the\s+life|daily\s+life|life\s+update|career\s+update|channel\s+update|tour\s+diary|travel\s+(?:vlog|diary)|road\s+trip|gaming|gameplay|lets?\s+play|challenges?|unboxing|q\s*&\s*a|questions?\s+and\s+answers?|news\s+(?:update|report)|breaking\s+news|announcements?|pranks?|comedy|funny\s+moments?|shorts?|skits?|documentar(?:y|ies)|meet\s+and\s+greet|press\s+conference|livestreams?)\b',
    caseSensitive: false,
  );

  bool _isMusicPlaylist(YoutubePublicPlaylist item) {
    if (item.id.trim().isEmpty || item.itemCount <= 0) return false;
    final title = item.title.trim();
    if (title.isEmpty || _nonMusicContentTitle.hasMatch(title)) return false;
    return true;
  }

  static final RegExp _unofficialContent = RegExp(
    r'\b(?:cover(?:ed)?|karaoke|fan[ -]?made|unofficial|reaction|reacts?|tribute|slowed|sped\s*up|nightcore|dance\s+practice|teasers?|trailers?|snippets?)\b',
    caseSensitive: false,
  );

  bool _isClearlyNonMusic(YoutubeSearchResult video) =>
      _nonMusicContentTitle.hasMatch(video.title);

  /// Lagu biasanya 45 detik sampai 15 menit; di luar itu umumnya mix,
  /// rekaman live panjang, atau klip pendek.
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

  /// Use the current search response to seed the artist catalogue. That means
  /// official releases uploaded by a label (not only tracks uploaded directly
  /// to the artist's own channel) can appear without an additional search.list
  /// request. Covers, karaoke, fan edits, and reactions are filtered out.
  List<YoutubeSearchResult> _filterArtistSearchResults(
    List<YoutubeSearchResult> source,
  ) {
    final artist = _normalizeArtistText(widget.artist);
    if (artist.isEmpty) return const [];

    final seen = <String>{};
    final tracks = <YoutubeSearchResult>[];
    final unofficialPattern = RegExp(
      r'\b(?:cover(?:ed)?|karaoke|fan[ -]?made|unofficial|reaction|reacts?|tribute|slowed|sped\s*up|nightcore|dance\s+practice)\b',
      caseSensitive: false,
    );
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

      final rawMetadata = '${video.title} ${video.description} ${video.channelTitle}';
      if (unofficialPattern.hasMatch(rawMetadata)) continue;
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
    setState(() {
      _loading = true;
      _error = null;
    });
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

          // Song list and album/playlist list are loaded independently, so a
          // playlist failure does not hide songs (and vice versa).
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
              // A channel can still expose albums/playlists even if uploads
              // cannot be read. Fall back to search if both sections are empty.
            }
          }

          try {
            final playlists = await _channelService.channelPlaylistsPage(
              channelId,
              maxResults: 50,
            );
            if (!mounted) return;
            _playlists = playlists.items
                .where(_isMusicPlaylist)
                .toList(growable: false);
            _nextPlaylistsToken = playlists.nextPageToken;
          } catch (_) {
            // Keep available songs if this channel has no accessible playlists.
          }
        } catch (_) {
          // Some tracks have stale channel IDs. The search fallback below
          // keeps the artist entry usable instead of failing the whole page.
        }
      }

      // Old search results and caches sometimes have no channelId. Keep the
      // existing artist search as fallback so the page still works for them.
      if (_songs.isEmpty && _playlists.isEmpty) {
        _usedSearchFallback = true;
        final searchResults = await widget.searchService.search(
          '${widget.artist} songs',
        );
        List<YoutubeSearchResult> enrichedResults;
        try {
          enrichedResults = await _channelService.withViewCounts(searchResults);
        } catch (_) {
          // Keep the page usable when videos.list is unavailable; title and
          // channel metadata are still filtered below.
          enrichedResults = searchResults;
        }
        final musicResults = enrichedResults.where((video) =>
            video.videoId.isNotEmpty &&
            !video.isLocal &&
            !video.isLive &&
            !video.isUpcoming &&
            !_isClearlyNonMusic(video) &&
            YoutubeSearchService.isMusicChannelUpload(
              video,
              channelTitle: video.channelTitle,
            )).toList(growable: false);
        final cleanResults = await widget.searchService.removeShorts(musicResults);
        final artistReleases = _filterArtistSearchResults(cleanResults);
        // Hanya lagu yang terbukti milik artis ini. Sebelumnya, bila tidak ada
        // yang cocok, 30 hasil pencarian apa pun ikut ditampilkan sehingga
        // lagu artis lain bisa muncul di halaman artis.
        _songs = _mergeTracks(artistReleases, _songs);
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
      // playlistItems.list does not include complete duration/category data.
      // Enrich in batches so Shorts and non-music clips are easier to reject.
      enriched = await _channelService.withViewCounts(source);
    } catch (_) {
      enriched = source;
    }
    final tracks = enriched.where((video) =>
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
        )).toList(growable: false);
    return widget.searchService.removeShorts(tracks);
  }

  Future<void> _loadMoreSongs() async {
    final token = _nextSongsToken;
    if (_loadingMoreSongs || token == null || _uploadsPlaylistId.isEmpty) return;
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

  Future<void> _loadMorePlaylists() async {
    final token = _nextPlaylistsToken;
    final channelId = widget.channelId.trim();
    if (_loadingMorePlaylists || token == null || channelId.isEmpty) return;
    setState(() => _loadingMorePlaylists = true);
    try {
      final page = await _channelService.channelPlaylistsPage(
        channelId,
        pageToken: token,
        maxResults: 50,
      );
      if (!mounted) return;
      final known = _playlists.map((playlist) => playlist.id).toSet();
      setState(() {
        _playlists = [
          ..._playlists,
          ...page.items.where((playlist) =>
              _isMusicPlaylist(playlist) && !known.contains(playlist.id)),
        ];
        _nextPlaylistsToken = page.nextPageToken;
      });
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _loadingMorePlaylists = false);
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
    if (widget.onPlayList != null && valid.isNotEmpty) {
      await widget.onPlayList!(selected, valid);
    } else {
      widget.onPlay(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_artistTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _songs.isEmpty && _playlists.isEmpty
              ? _ErrorState(message: _error.toString(), onRetry: _load)
              : Column(
                  children: [
                    _header(scheme),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(child: _tabButton(0, 'Lagu', Icons.music_note_rounded)),
                          const SizedBox(width: 8),
                          Expanded(child: _tabButton(1, 'Album & playlist', Icons.album_rounded)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _tab == 0 ? _buildSongList() : _buildPlaylistList(),
                    ),
                  ],
                ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.96),
            scheme.secondaryContainer.withValues(alpha: 0.74),
            scheme.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 78,
              height: 78,
              child: _details?.avatarUrl.isNotEmpty == true
                  ? Image.network(
                      _details!.avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _artistPlaceholder(scheme),
                    )
                  : _artistPlaceholder(scheme),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _details == null ? 'RADIO ARTIS' : 'ARTIS / CHANNEL',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _artistTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, height: 1.05),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_songs.length} lagu · ${_playlists.length} album/playlist',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _songs.isEmpty
                          ? null
                          : () => unawaited(_playTracks(_songs.first, _songs)),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Putar semua'),
                    ),
                    if (_playlists.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _tab = 1),
                        icon: const Icon(Icons.album_rounded, size: 17),
                        label: const Text('Rilisan'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _artistPlaceholder(ColorScheme scheme) => Container(
        color: scheme.primary,
        alignment: Alignment.center,
        child: const Icon(Icons.graphic_eq_rounded, size: 38, color: Colors.white),
      );

  Widget _tabButton(int index, String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _tab == index;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _tab = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSongList() {
    if (_songs.isEmpty) {
      return _EmptyState(
        icon: Icons.music_off_rounded,
        title: 'Lagu musik belum ditemukan',
        subtitle: _nextSongsToken != null && _uploadsPlaylistId.isNotEmpty
            ? 'Unggahan terbaru tidak berisi lagu yang cocok. Muat unggahan berikutnya untuk mencari rilisan musik.'
            : 'Tidak ada unggahan yang dikenali sebagai lagu. Coba buka artis dari lagu atau channel musik lainnya.',
        actionLabel: _nextSongsToken != null && _uploadsPlaylistId.isNotEmpty
            ? 'Muat unggahan berikutnya'
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
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index >= _songs.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: OutlinedButton.icon(
                onPressed: _loadingMoreSongs ? null : _loadMoreSongs,
                icon: _loadingMoreSongs
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.expand_more_rounded),
                label: Text(_loadingMoreSongs ? 'Memuat...' : 'Muat lagu lainnya'),
              ),
            ),
          );
        }
        return _SongTile(
          video: _songs[index],
          onTap: () => unawaited(_playTracks(_songs[index], _songs)),
          onLongPress: widget.onLongPress == null ? null : () => widget.onLongPress!(_songs[index]),
          subtitle: _songs[index].publishedAt == null ? _songs[index].channelTitle :
              '${_songs[index].channelTitle} · ${_songs[index].publishedAt!.year}',
        );
      },
    );
  }

  Widget _buildPlaylistList() {
    if (_playlists.isEmpty) {
      return _EmptyState(
        icon: Icons.album_rounded,
        title: 'Album musik belum ditemukan',
        subtitle: _nextPlaylistsToken != null
            ? 'Playlist pada halaman ini terfilter sebagai konten nonmusik. Muat daftar berikutnya untuk mencari album atau playlist lagu.'
            : 'Channel ini tidak memiliki album atau playlist musik publik yang dikenali.',
        actionLabel: _nextPlaylistsToken != null ? 'Muat playlist berikutnya' : null,
        onAction: _nextPlaylistsToken != null ? _loadMorePlaylists : null,
        actionLoading: _loadingMorePlaylists,
      );
    }
    final hasMore = _nextPlaylistsToken != null;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      itemCount: _playlists.length + (hasMore || _loadingMorePlaylists ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= _playlists.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: OutlinedButton.icon(
                onPressed: _loadingMorePlaylists ? null : _loadMorePlaylists,
                icon: _loadingMorePlaylists
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.expand_more_rounded),
                label: Text(_loadingMorePlaylists ? 'Memuat...' : 'Muat rilisan lainnya'),
              ),
            ),
          );
        }
        return _AlbumPlaylistTile(
          playlist: _playlists[index],
          channelService: _channelService,
          searchService: widget.searchService,
          channelTitle: _artistTitle,
          channelDescription: _details?.description ?? '',
          onPlay: widget.onPlay,
          onPlayList: widget.onPlayList,
          onLongPress: widget.onLongPress,
        );
      },
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.video,
    required this.onTap,
    this.onLongPress,
    required this.subtitle,
  });

  final YoutubeSearchResult video;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: UnifiedArtwork(
                  track: video,
                  width: 74,
                  height: 64,
                  cacheWidth: 240,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_circle_fill_rounded, size: 29, color: appGold),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumPlaylistTile extends StatefulWidget {
  const _AlbumPlaylistTile({
    required this.playlist,
    required this.channelService,
    required this.searchService,
    required this.channelTitle,
    required this.channelDescription,
    required this.onPlay,
    required this.onPlayList,
    required this.onLongPress,
  });

  final YoutubePublicPlaylist playlist;
  final YoutubePublicChannelService channelService;
  final YoutubeSearchService searchService;
  final String channelTitle;
  final String channelDescription;
  final ValueChanged<YoutubeSearchResult> onPlay;
  final Future<void> Function(YoutubeSearchResult, List<YoutubeSearchResult>)? onPlayList;
  final ValueChanged<YoutubeSearchResult>? onLongPress;

  @override
  State<_AlbumPlaylistTile> createState() => _AlbumPlaylistTileState();
}

class _AlbumPlaylistTileState extends State<_AlbumPlaylistTile> {
  List<YoutubeSearchResult> _tracks = const [];
  String? _nextToken;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;

  Future<void> _load({bool more = false}) async {
    if (_loading || _loadingMore) return;
    if (more && _nextToken == null) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final page = await widget.channelService.playlistItemsPage(
        widget.playlist.id,
        pageToken: more ? _nextToken : null,
        maxResults: 50,
      );
      List<YoutubeSearchResult> enriched;
      try {
        enriched = await widget.channelService.withViewCounts(page.items);
      } catch (_) {
        // Don't lose a playlist if metadata enrichment fails; the title-based
        // music filter still excludes obvious vlogs/interviews/reactions.
        enriched = page.items;
      }
      final filtered = enriched.where((track) =>
          track.videoId.isNotEmpty &&
          !track.isLocal &&
          !track.isLive &&
          !track.isUpcoming &&
          track.title.toLowerCase() != '[deleted video]' &&
          track.title.toLowerCase() != 'private video' &&
          !_ArtistPageState._nonMusicContentTitle.hasMatch(track.title) &&
          YoutubeSearchService.isMusicChannelUpload(
            track,
            channelTitle: widget.channelTitle,
            channelDescription: widget.channelDescription,
          )).toList(growable: false);
      final musicTracks = await widget.searchService.removeShorts(filtered);
      if (!mounted) return;
      final known = _tracks.map((track) => track.videoId).toSet();
      final tracks = musicTracks
          .where((track) => !known.contains(track.videoId))
          .toList(growable: false);
      setState(() {
        _tracks = [..._tracks, ...tracks];
        _nextToken = page.nextPageToken;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _play(YoutubeSearchResult track) async {
    if (widget.onPlayList != null && _tracks.isNotEmpty) {
      await widget.onPlayList!(track, _tracks);
    } else {
      widget.onPlay(track);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHighest,
      child: ExpansionTile(
        key: PageStorageKey<String>('artist-playlist-${widget.playlist.id}'),
        initiallyExpanded: false,
        onExpansionChanged: (expanded) {
          if (expanded && _tracks.isEmpty && !_loading) unawaited(_load());
        },
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 62,
            height: 62,
            child: widget.playlist.thumbnailUrl.isNotEmpty
                ? Image.network(
                    widget.playlist.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _playlistPlaceholder(scheme),
                  )
                : _playlistPlaceholder(scheme),
          ),
        ),
        title: Text(widget.playlist.title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        subtitle: Text(
          _tracks.isEmpty
              ? 'Playlist publik · ${widget.playlist.itemCount} video'
              : '${_tracks.length} lagu musik',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
        ),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null && _tracks.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: Column(
                children: [
                  Text(_error.toString(), style: TextStyle(color: scheme.error, fontSize: 12)),
                  TextButton.icon(onPressed: () => unawaited(_load()), icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
                ],
              ),
            )
          else if (_tracks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Text('Tidak ada lagu musik di halaman playlist ini.'),
                  if (_nextToken != null)
                    TextButton.icon(
                      onPressed: _loadingMore
                          ? null
                          : () => unawaited(_load(more: true)),
                      icon: _loadingMore
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: Text(
                        _loadingMore ? 'Memuat...' : 'Cari lagu di halaman berikutnya',
                      ),
                    ),
                ],
              ),
            )
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FilledButton.tonalIcon(
                  onPressed: () => unawaited(_play(_tracks.first)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Putar playlist'),
                ),
              ),
            ),
            ..._tracks.map((track) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.music_note_rounded),
                  title: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(track.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  trailing: const Icon(Icons.play_circle_outline_rounded, color: appGold),
                  onTap: () => unawaited(_play(track)),
                  onLongPress: widget.onLongPress == null ? null : () => widget.onLongPress!(track),
                )),
            if (_nextToken != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextButton.icon(
                  onPressed: _loadingMore ? null : () => unawaited(_load(more: true)),
                  icon: _loadingMore
                      ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(_loadingMore ? 'Memuat...' : 'Muat track berikutnya'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _playlistPlaceholder(ColorScheme scheme) => Container(
        color: scheme.secondaryContainer,
        alignment: Alignment.center,
        child: Icon(Icons.album_rounded, color: scheme.onSecondaryContainer, size: 28),
      );
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
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
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
