import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/native_youtube_state.dart';
import '../models/player_ui_state.dart';
import '../models/loop_mode.dart';
import '../models/youtube_search_result.dart';
import '../services/youtube_live_chat_service.dart';
import '../services/youtube_video_service.dart';
import 'channel_avatar.dart';
import 'live_badge.dart';
import 'lyrics_panel.dart';
import '../utils/time_formatters.dart';

enum YoutubeCommentSort {
  relevance,
  newest,
  popular,
  replies,
}

extension YoutubeCommentSortLabel on YoutubeCommentSort {
  String get label {
    switch (this) {
      case YoutubeCommentSort.relevance:
        return 'Paling relevan';
      case YoutubeCommentSort.newest:
        return 'Terbaru';
      case YoutubeCommentSort.popular:
        return 'Terpopuler';
      case YoutubeCommentSort.replies:
        return 'Balasan terbanyak';
    }
  }
}

class YoutubeWatchPage extends StatefulWidget {
  final YoutubeSearchResult video;
  final VoidCallback onBack;
  final VoidCallback? onPip;
  final Future<void> Function()? onPlayNext;
  final Future<void> Function(YoutubeSearchResult video) onPlay;
  final bool signedIn;
  final bool subscribed;
  final Future<void> Function(String channelId)? onSubscribe;
  final Future<void> Function(String videoId, String rating)? onRate;
  final void Function(String channelId, String title)? onOpenChannel;
  final Future<void> Function()? onToggleLandscape;
  final VoidCallback? onToggleShuffle;
  final VoidCallback? onToggleSmartShuffle;
  final VoidCallback? onCycleLoopMode;
  final bool shuffleEnabled;
  final bool smartShuffleEnabled;
  final LoopModeCustom loopMode;
  final ValueNotifier<bool>? landscapeDiscussionVisible;

  /// Posisi putar native; dipakai menyinkronkan chat ulang (replay).
  final ValueListenable<NativeYoutubeState>? nativeState;
  final ValueListenable<PlayerUiState>? playerUiState;
  final Future<void> Function(Duration position)? onSeekFromLyrics;

  const YoutubeWatchPage({
    super.key,
    required this.video,
    required this.onBack,
    this.onPip,
    required this.onPlay,
    required this.signedIn,
    required this.subscribed,
    this.onPlayNext,
    this.onSubscribe,
    this.onRate,
    this.onOpenChannel,
    this.onToggleLandscape,
    this.onToggleShuffle,
    this.onToggleSmartShuffle,
    this.onCycleLoopMode,
    this.shuffleEnabled = false,
    this.smartShuffleEnabled = false,
    this.loopMode = LoopModeCustom.off,
    this.landscapeDiscussionVisible,
    this.nativeState,
    this.playerUiState,
    this.onSeekFromLyrics,
  });

  @override
  State<YoutubeWatchPage> createState() => _YoutubeWatchPageState();
}

class _YoutubeWatchPageState extends State<YoutubeWatchPage> {
  final GlobalKey _lyricsKey = GlobalKey();
  final _service = YoutubeVideoService();
  YoutubeVideoDetails? _details;
  List<YoutubeComment> _comments = const [];
  final Map<String, List<YoutubeCommentReply>> _commentReplies = <String, List<YoutubeCommentReply>>{};
  final Set<String> _expandedReplies = <String>{};
  final Set<String> _replyLoading = <String>{};
  bool _commentsLoading = false;
  YoutubeCommentSort _commentSort = YoutubeCommentSort.relevance;
  int _commentRequestId = 0;
  bool _descriptionExpanded = false;
  bool _subscribing = false;
  bool _subscribed = false;
  String? _error;
  bool _discussionVisible = false;
  bool _showLiveChat = false;
  bool _liveAvailable = false;
  bool _livePolling = false;
  bool _liveLoading = false;
  final List<LiveChatMessage> _liveChat = <LiveChatMessage>[];
  final Set<String> _liveChatIds = <String>{};
  final YoutubeLiveChatService _liveService = YoutubeLiveChatService();
  final ScrollController _liveScroll = ScrollController();
  Timer? _liveChatTimer;
  String? _liveContinuation;
  int _livePollGeneration = 0;
  bool? _lastLandscape;

  void _onLandscapeDiscussionVisibilityChanged() {
    if (!mounted) return;
    final next = widget.landscapeDiscussionVisible?.value ?? false;
    if (next == _discussionVisible) return;
    if (next) {
      unawaited(_loadDiscussion());
    } else {
      setState(() => _discussionVisible = false);
      _syncLivePolling();
    }
  }

  @override
  void initState() {
    super.initState();
    _subscribed = widget.subscribed;
    widget.landscapeDiscussionVisible?.addListener(_onLandscapeDiscussionVisibilityChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant YoutubeWatchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.landscapeDiscussionVisible != widget.landscapeDiscussionVisible) {
      oldWidget.landscapeDiscussionVisible?.removeListener(_onLandscapeDiscussionVisibilityChanged);
      widget.landscapeDiscussionVisible?.addListener(_onLandscapeDiscussionVisibilityChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final changed = _lastLandscape != null && _lastLandscape != isLandscape;
    _lastLandscape = isLandscape;
    if (changed) {
      // didChangeDependencies dipanggil saat Flutter sedang membangun frame.
      // Jangan mengubah ValueNotifier di sini karena listener parent dapat
      // langsung memicu rebuild lain dan menghasilkan "setState/markNeedsBuild
      // called during build". Jadwalkan reset setelah frame selesai.
      // Live chat tetap dipilih; hanya panel landscape yang ditutup.
      _discussionVisible = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncLivePolling();
      });
      final notifier = widget.landscapeDiscussionVisible;
      if (notifier?.value == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final currentNotifier = widget.landscapeDiscussionVisible;
          if (currentNotifier != null && currentNotifier.value) {
            currentNotifier.value = false;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _livePollGeneration++;
    _liveChatTimer?.cancel();
    _liveReprobeTimer?.cancel();
    _replayTicker?.cancel();
    _replayGeneration++;
    _liveScroll.dispose();
    _liveService.close();
    widget.landscapeDiscussionVisible?.removeListener(_onLandscapeDiscussionVisibilityChanged);
    super.dispose();
  }

  Future<void> _load() async {
    unawaited(_probeLiveChat());
    try {
      final details = await _service.details(widget.video.videoId);
      if (!mounted) return;
      setState(() => _details = details);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  bool get _isLandscapeNow {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height;
  }

  String get _commentApiOrder =>
      _commentSort == YoutubeCommentSort.newest ? 'time' : 'relevance';

  List<YoutubeComment> _sortLoadedComments(List<YoutubeComment> comments) {
    final sorted = [...comments];
    switch (_commentSort) {
      case YoutubeCommentSort.relevance:
      case YoutubeCommentSort.newest:
        return sorted;
      case YoutubeCommentSort.popular:
        sorted.sort((a, b) {
          final likes = b.likeCount.compareTo(a.likeCount);
          if (likes != 0) return likes;
          return b.replyCount.compareTo(a.replyCount);
        });
        return sorted;
      case YoutubeCommentSort.replies:
        sorted.sort((a, b) {
          final replies = b.replyCount.compareTo(a.replyCount);
          if (replies != 0) return replies;
          return b.likeCount.compareTo(a.likeCount);
        });
        return sorted;
    }
  }

  Future<void> _loadDiscussion() async {
    if (!mounted) return;
    if (_isLandscapeNow && widget.landscapeDiscussionVisible?.value != true) {
      widget.landscapeDiscussionVisible?.value = true;
    }

    final requestId = ++_commentRequestId;
    setState(() {
      _discussionVisible = true;
      _commentsLoading = true;
      _error = null;
    });
    _syncLivePolling();
    try {
      final comments = await _service.comments(
        widget.video.videoId,
        order: _commentApiOrder,
      );
      if (!mounted || requestId != _commentRequestId) return;
      setState(() {
        _comments = _sortLoadedComments(comments);
        _commentsLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _commentRequestId) return;
      setState(() {
        _commentsLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _setCommentSort(YoutubeCommentSort sort) async {
    if (_commentSort == sort && !_commentsLoading) return;
    setState(() => _commentSort = sort);
    await _loadDiscussion();
  }

  // ------------------------------------------------------------ live chat

  bool _liveIsReplay = false;
  bool _liveEnded = false;
  int _liveFailures = 0;
  int _liveReprobeCount = 0;
  Timer? _liveReprobeTimer;

  // Chat ulang (replay): pesan diambil per potongan lalu ditampilkan sesuai
  // posisi putar video.
  String? _replayStartToken;
  final List<LiveChatMessage> _replayPending = <LiveChatMessage>[];
  Timer? _replayTicker;
  bool _replayFetching = false;
  int _replayLastPosMs = 0;
  int _replayGeneration = 0;

  /// Cek apakah video ini punya chat: siaran langsung ATAU chat ulang dari
  /// siaran yang sudah selesai. Kalau ya, tab chat langsung jadi tab utama.
  /// Gagal jaringan / siaran yang belum mulai dicoba lagi berkala.
  Future<void> _probeLiveChat() async {
    final result = await _liveService.open(widget.video.videoId);
    if (!mounted) return;
    final session = result.session;
    if (session == null) {
      final mayAppear =
          result.failed || widget.video.isLive || widget.video.isUpcoming;
      if (mayAppear && !_liveAvailable && _liveReprobeCount < 12) {
        _liveReprobeCount++;
        _liveReprobeTimer?.cancel();
        _liveReprobeTimer = Timer(
          const Duration(seconds: 20),
          () => unawaited(_probeLiveChat()),
        );
      }
      return;
    }
    _liveReprobeTimer?.cancel();
    setState(() {
      _liveAvailable = true;
      _showLiveChat = true;
      _liveIsReplay = session.isReplay;
      _liveEnded = false;
      _liveFailures = 0;
      _liveContinuation = session.continuation;
      _replayStartToken = session.continuation;
      _liveLoading = true;
    });
    _syncLivePolling();
  }

  /// Panel live chat sedang terlihat? (portrait: selalu; landscape: saat panel dibuka)
  bool get _liveChatShouldRun {
    if (!_liveAvailable || !_showLiveChat) return false;
    if (!mounted) return false;
    if (!_isLandscapeNow) return true;
    return widget.landscapeDiscussionVisible?.value ?? _discussionVisible;
  }

  int _currentPositionMs() {
    final state = widget.nativeState?.value;
    if (state == null) return 0;
    if (state.videoId.isNotEmpty && state.videoId != widget.video.videoId) {
      return 0;
    }
    return state.position.inMilliseconds;
  }

  /// Menyalakan/mematikan polling sesuai visibilitas panel agar hemat data.
  void _syncLivePolling() {
    if (!mounted) return;
    final shouldRun = _liveChatShouldRun;

    if (_liveIsReplay) {
      if (shouldRun && _replayTicker == null) {
        _replayLastPosMs = _currentPositionMs();
        _replayTicker = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => _replayTick(),
        );
        _replayTick();
      } else if (!shouldRun && _replayTicker != null) {
        _replayTicker?.cancel();
        _replayTicker = null;
      }
      return;
    }

    if (_liveEnded) return;
    if (shouldRun && !_livePolling) {
      _livePolling = true;
      final generation = ++_livePollGeneration;
      unawaited(_pollLiveChat(generation));
    } else if (!shouldRun && _livePolling) {
      _livePolling = false;
      _livePollGeneration++;
      _liveChatTimer?.cancel();
    }
  }

  void _finishLive() {
    _livePolling = false;
    _liveChatTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _liveEnded = true;
      _liveLoading = false;
    });
  }

  Future<void> _pollLiveChat(int generation) async {
    if (!mounted || generation != _livePollGeneration) return;
    var delay = 5000;
    try {
      final token = _liveContinuation;
      if (token == null) {
        _livePolling = false;
        if (mounted) setState(() => _liveLoading = false);
        return;
      }
      final batch = await _liveService.poll(token);
      if (!mounted || generation != _livePollGeneration) return;

      if (batch.failed) {
        // Gagal sesaat (jaringan / token kedaluwarsa): coba lagi, jangan
        // langsung menganggap siaran berakhir.
        _liveFailures++;
        delay = (4000 * _liveFailures).clamp(4000, 15000).toInt();
        if (_liveFailures >= 3) {
          final reopened = await _liveService.open(widget.video.videoId);
          if (!mounted || generation != _livePollGeneration) return;
          final session = reopened.session;
          if (session != null && !session.isReplay) {
            _liveContinuation = session.continuation;
            _liveFailures = 0;
            delay = 2000;
          } else if (!reopened.failed) {
            // Chat live sudah tidak ada (siaran selesai / chat ditutup).
            _finishLive();
            return;
          }
        }
        if (mounted && _liveLoading && _liveFailures >= 3) {
          setState(() => _liveLoading = false);
        }
      } else {
        _liveFailures = 0;
        final wasNearBottom = !_liveScroll.hasClients ||
            _liveScroll.position.maxScrollExtent -
                    _liveScroll.position.pixels <
                80;
        setState(() {
          _liveLoading = false;
          for (final message in batch.messages) {
            if (_liveChatIds.add(message.id)) _liveChat.add(message);
          }
          _trimLiveChat();
          if (batch.nextContinuation != null) {
            _liveContinuation = batch.nextContinuation;
          }
        });
        delay = batch.pollMillis;
        if (batch.nextContinuation == null) {
          // Siaran berakhir atau chat ditutup.
          _finishLive();
          return;
        }
        if (wasNearBottom) _scrollLiveToBottom();
      }
    } catch (_) {
      delay = 7000;
    }
    if (!mounted || generation != _livePollGeneration) return;
    _liveChatTimer?.cancel();
    _liveChatTimer = Timer(
      Duration(milliseconds: delay),
      () => unawaited(_pollLiveChat(generation)),
    );
  }

  void _trimLiveChat() {
    if (_liveChat.length <= 150) return;
    final removed = _liveChat.length - 150;
    for (final old in _liveChat.take(removed)) {
      _liveChatIds.remove(old.id);
    }
    _liveChat.removeRange(0, removed);
  }

  // ------------------------------------------------------- chat ulang

  void _replayTick() {
    if (!mounted || !_liveIsReplay) return;
    final pos = _currentPositionMs();
    // Loncat (seek) maju/mundur: mulai ulang dari posisi baru.
    final jumped =
        pos < _replayLastPosMs - 2000 || pos > _replayLastPosMs + 8000;
    _replayLastPosMs = pos;
    if (jumped) {
      _resetReplay(pos);
      return;
    }

    var changed = false;
    while (_replayPending.isNotEmpty && _replayPending.first.offsetMs <= pos) {
      final message = _replayPending.removeAt(0);
      if (_liveChatIds.add(message.id)) {
        _liveChat.add(message);
        changed = true;
      }
    }
    if (changed) {
      final wasNearBottom = !_liveScroll.hasClients ||
          _liveScroll.position.maxScrollExtent - _liveScroll.position.pixels <
              80;
      setState(() {
        _liveLoading = false;
        _trimLiveChat();
      });
      if (wasNearBottom) _scrollLiveToBottom();
    }

    if (_replayPending.length < 40 &&
        !_replayFetching &&
        _liveContinuation != null) {
      unawaited(_fetchReplay(_replayGeneration, pos));
    }
  }

  void _resetReplay(int pos) {
    _replayGeneration++;
    _replayPending.clear();
    _replayFetching = false;
    _liveContinuation = _replayStartToken;
    _liveFailures = 0;
    setState(() {
      _liveChat.clear();
      _liveChatIds.clear();
      _liveLoading = true;
    });
    unawaited(_fetchReplay(_replayGeneration, pos));
  }

  Future<void> _fetchReplay(int generation, int offsetMs) async {
    final token = _liveContinuation;
    if (token == null || _replayFetching) return;
    _replayFetching = true;
    try {
      final batch = await _liveService.pollReplay(token, offsetMs);
      if (!mounted || generation != _replayGeneration) return;
      if (batch.failed) {
        _liveFailures++;
        if (_liveFailures >= 4) {
          // Berhenti mencoba terus-menerus; tampilkan keadaan kosong.
          _liveContinuation = null;
          setState(() => _liveLoading = false);
        }
        return;
      }
      _liveFailures = 0;
      _replayPending.addAll(batch.messages);
      _replayPending.sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
      _liveContinuation = batch.nextContinuation;
      if (_liveLoading && batch.messages.isEmpty) {
        setState(() => _liveLoading = false);
      }
    } finally {
      if (generation == _replayGeneration) _replayFetching = false;
    }
  }

  void _scrollLiveToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_liveScroll.hasClients) return;
      _liveScroll.animateTo(
        _liveScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _liveMessageTile(LiveChatMessage message) {
    final scheme = Theme.of(context).colorScheme;
    final nameColor = message.isOwner
        ? scheme.primary
        : message.isModerator
            ? Colors.lightBlueAccent
            : scheme.onSurfaceVariant;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: scheme.surfaceContainerHighest,
          backgroundImage: message.avatarUrl.isNotEmpty ? NetworkImage(message.avatarUrl) : null,
          child: message.avatarUrl.isEmpty ? const Icon(Icons.person_outline_rounded, size: 13) : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: message.author,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: nameColor),
                ),
                if (message.isOwner || message.isModerator)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Icon(
                        message.isOwner ? Icons.verified_rounded : Icons.build_circle_rounded,
                        size: 13,
                        color: nameColor,
                      ),
                    ),
                  ),
                if (message.sentAt != null && !_liveIsReplay)
                  TextSpan(
                    text: '  ${formatClockTime(message.sentAt)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (_liveIsReplay && message.offsetMs > 0)
                  TextSpan(
                    text: '  ${formatVideoOffset(message.offsetMs)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const TextSpan(text: '  '),
                TextSpan(text: message.text, style: const TextStyle(fontSize: 13, height: 1.3)),
              ],
            ),
          ),
        ),
      ],
    );
    if (message.amount.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: row);
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.amount,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: scheme.onTertiaryContainer),
          ),
          const SizedBox(height: 4),
          row,
        ],
      ),
    );
  }

  /// Daftar live chat (dipakai portrait dan landscape).
  Widget _liveChatList(ColorScheme scheme) {
    if (_liveChat.isEmpty) {
      final String message;
      if (_liveEnded) {
        message = 'Siaran berakhir atau chat ditutup.';
      } else if (_liveFailures >= 3) {
        message = 'Chat gagal dimuat, mencoba lagi…';
      } else if (_liveIsReplay) {
        message = 'Belum ada chat di bagian video ini.';
      } else {
        message = 'Menunggu pesan baru…';
      }
      return Center(
        child: _liveLoading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
      );
    }
    final showFooter = _liveEnded && !_liveIsReplay;
    return ListView.builder(
      controller: _liveScroll,
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      itemCount: _liveChat.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _liveChat.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Siaran berakhir atau chat ditutup.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          );
        }
        return _liveMessageTile(_liveChat[index]);
      },
    );
  }

  Widget _livePortraitBox(ColorScheme scheme) {
    return Container(
      height: 380,
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: _liveChatList(scheme),
    );
  }

  List<Widget> _commentSlivers(ColorScheme scheme) {
    if (_commentsLoading) {
      return const [
        SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
      ];
    }
    if (_comments.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            child: Text(_error ?? 'Belum ada komentar.', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        sliver: SliverList.builder(
          itemCount: _comments.length,
          itemBuilder: (context, index) => _commentTile(_comments[index]),
        ),
      ),
    ];
  }

  Widget _commentSortDropdown(ColorScheme scheme) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<YoutubeCommentSort>(
          value: _commentSort,
          isDense: true,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          menuMaxHeight: 320,
          borderRadius: BorderRadius.circular(12),
          items: YoutubeCommentSort.values
              .map(
                (sort) => DropdownMenuItem<YoutubeCommentSort>(
                  value: sort,
                  child: Text(
                    sort.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
              )
              .toList(),
          onChanged: _commentsLoading
              ? null
              : (sort) {
                  if (sort != null) unawaited(_setCommentSort(sort));
                },
        ),
      ),
    );
  }

  Widget _discussionTitle(BuildContext context, {bool landscape = false}) {
    final scheme = Theme.of(context).colorScheme;
    final liveAvailable = _liveAvailable;
    final showingComments = !liveAvailable || !_showLiveChat;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 16, landscape ? 8 : 14, 6),
      child: Column(
        children: [
          Row(
            children: [
              if (liveAvailable)
                Expanded(
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment<bool>(
                        value: true,
                        icon: const Icon(Icons.sensors_rounded, size: 16),
                        label: Text(_liveIsReplay ? 'Chat ulang' : 'Live chat'),
                      ),
                      const ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.comment_outlined, size: 16),
                        label: Text('Komentar'),
                      ),
                    ],
                    selected: {_showLiveChat},
                    onSelectionChanged: (value) {
                      setState(() => _showLiveChat = value.first);
                      if (!value.first && _comments.isEmpty && !_commentsLoading) {
                        unawaited(_loadDiscussion());
                      }
                      _syncLivePolling();
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(
                        const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                )
              else
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Komentar',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              if (landscape)
                IconButton(
                  tooltip: 'Sembunyikan panel',
                  onPressed: () {
                    if (widget.landscapeDiscussionVisible != null) {
                      widget.landscapeDiscussionVisible!.value = false;
                    } else {
                      setState(() => _discussionVisible = false);
                    }
                  },
                  icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          if (showingComments) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.sort_rounded, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Urutkan',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                _commentSortDropdown(scheme),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatViews(int value) {
    if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)} M';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} jt';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} rb';
    return value.toString();
  }


  Widget _channelRow() {
    final scheme = Theme.of(context).colorScheme;
    final details = _details;
    final channelTitle = details?.channelTitle ?? widget.video.channelTitle;
    final resolvedChannelId = details?.channelId.trim().isNotEmpty == true
        ? details!.channelId.trim()
        : widget.video.channelId.trim();
    final channelId = resolvedChannelId;
    final canOpen = widget.onOpenChannel != null && channelId.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: canOpen ? () => widget.onOpenChannel!(channelId, channelTitle) : null,
            child: Row(
              children: [
                ChannelAvatar(
                  channelId: channelId,
                  videoId: widget.video.videoId,
                  name: channelTitle,
                  radius: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!widget.signedIn)
          const SizedBox.shrink()
        else
          FilledButton(
            onPressed: _subscribing || widget.onSubscribe == null || details?.channelId.isEmpty != false
                ? null
                : () async {
                    setState(() => _subscribing = true);
                    try {
                      await widget.onSubscribe!(details!.channelId);
                      if (mounted) setState(() => _subscribed = true);
                    } finally {
                      if (mounted) setState(() => _subscribing = false);
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: _subscribed
                  ? scheme.surfaceContainerHigh
                  : Colors.white,
              foregroundColor: _subscribed ? scheme.onSurface : Colors.black,
              disabledBackgroundColor: scheme.surfaceContainerHigh,
              disabledForegroundColor: scheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            child: Text(_subscribed ? 'Subscribed' : 'Subscribe'),
          ),
      ],
    );
  }

  Future<void> _toggleReplies(YoutubeComment comment) async {
    if (comment.replyCount <= 0) return;
    if (_expandedReplies.contains(comment.id)) {
      setState(() => _expandedReplies.remove(comment.id));
      return;
    }

    setState(() {
      _expandedReplies.add(comment.id);
    });

    if (_commentReplies.containsKey(comment.id) || _replyLoading.contains(comment.id)) {
      return;
    }

    setState(() => _replyLoading.add(comment.id));
    try {
      final fetched = await _service.replies(comment.id);
      if (!mounted) return;
      setState(() {
        _commentReplies[comment.id] = fetched;
        _replyLoading.remove(comment.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentReplies[comment.id] = comment.replies;
        _replyLoading.remove(comment.id);
      });
    }
  }

  Widget _replyTile(YoutubeCommentReply reply) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 34),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundImage: reply.authorAvatarUrl.isNotEmpty ? NetworkImage(reply.authorAvatarUrl) : null,
            child: reply.authorAvatarUrl.isEmpty ? const Icon(Icons.person_outline_rounded, size: 14) : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reply.author, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 3),
                Text(reply.text, style: const TextStyle(height: 1.3, fontSize: 12.5)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${reply.likeCount} suka', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5)),
                    if (reply.publishedAt != null)
                      Text(
                        formatRelativeTime(reply.publishedAt),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5),
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

  Widget _commentTile(YoutubeComment comment) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: comment.authorAvatarUrl.isNotEmpty ? NetworkImage(comment.authorAvatarUrl) : null,
            child: comment.authorAvatarUrl.isEmpty ? const Icon(Icons.person_outline_rounded, size: 18) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comment.author, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 4),
                Text(comment.text, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 7),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${comment.likeCount} suka',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
                    ),
                    if (comment.publishedAt != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        formatRelativeTime(comment.publishedAt),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
                      ),
                    ],
                    if (comment.replyCount > 0) ...[
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => unawaited(_toggleReplies(comment)),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _expandedReplies.contains(comment.id)
                              ? 'Sembunyikan balasan'
                              : 'Lihat ${comment.replyCount} balasan',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_expandedReplies.contains(comment.id)) ...[
                  if (_replyLoading.contains(comment.id))
                    const Padding(
                      padding: EdgeInsets.only(left: 34, top: 8),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else
                    ...(_commentReplies[comment.id] ?? comment.replies).map(_replyTile),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeOverlay(BuildContext context, ColorScheme scheme) {
    final size = MediaQuery.sizeOf(context);
    final panelWidth = (size.width * 0.38).clamp(320.0, 440.0).toDouble();
    final discussionVisible = widget.landscapeDiscussionVisible?.value ?? _discussionVisible;

    final discussionContent = Material(
      color: scheme.surface,
      elevation: 18,
      child: SafeArea(
        left: false,
        top: true,
        bottom: true,
        child: Column(
          children: [
            _discussionTitle(context, landscape: true),
            Expanded(
              child: _liveAvailable && _showLiveChat
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                      child: _liveChatList(scheme),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 22),
                      children: [
                        if (_commentsLoading)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_comments.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              _error ?? 'Belum ada komentar.',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          )
                        else
                          ..._comments.map(_commentTile),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: discussionVisible ? 0 : -panelWidth - 12,
            width: panelWidth,
            child: discussionContent,
          ),
        ],
      ),
    );
  }

  void _scrollToLyrics() {
    if (_lyricsKey.currentContext != null) {
      Scrollable.ensureVisible(
        _lyricsKey.currentContext!,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lirik belum tersedia untuk video ini.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageSize = MediaQuery.sizeOf(context);
    final isLandscape = pageSize.width > pageSize.height;
    final details = _details;
    final title = details?.title ?? widget.video.title;
    final description = details?.description ?? '';
    final views = details?.viewCount ?? widget.video.viewCount;
    final isLive = widget.video.isLive || widget.video.liveStatus.isNotEmpty;

    if (isLandscape) {
      return _buildLandscapeOverlay(context, scheme);
    }

    final statText = <String>[];
    if (views != null) statText.add('${_formatViews(views)} views');
    if (details?.publishedAt != null) {
      statText.add('${details!.publishedAt!.day}/${details.publishedAt!.month}/${details.publishedAt!.year}');
    }

    return Material(
      color: scheme.surface,
      child: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35))),
              ),
              child: Row(
                children: [
                  IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Kembali'),
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                  IconButton(onPressed: widget.onPip, tooltip: 'Mini player', icon: const Icon(Icons.picture_in_picture_alt_outlined)),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            letterSpacing: -0.15,
                          ),
                        ),
                      ),
                      if (isLive) ...[
                        const SizedBox(width: 8),
                        LiveBadge(video: widget.video),
                      ],
                    ],
                  ),
                  if (statText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      statText.join(' • '),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: Row(
                children: [Expanded(child: _channelRow())],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 64,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                scrollDirection: Axis.horizontal,
                itemCount: 9,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  late IconData icon;
                  late String label;
                  VoidCallback? action;
                  bool selected = false;
                  switch (index) {
                    case 0:
                      icon = Icons.thumb_up_alt_outlined;
                      label = _formatViews(details?.likeCount ?? 0);
                      action = widget.onRate == null ? null : () => widget.onRate!(widget.video.videoId, 'like');
                      break;
                    case 1:
                      icon = Icons.thumb_down_alt_outlined;
                      label = 'Tidak suka';
                      action = widget.onRate == null ? null : () => widget.onRate!(widget.video.videoId, 'dislike');
                      break;
                    case 2:
                      icon = Icons.shuffle_rounded;
                      label = widget.shuffleEnabled ? 'Shuffle' : 'Acak';
                      selected = widget.shuffleEnabled;
                      action = widget.onToggleShuffle;
                      break;
                    case 3:
                      icon = Icons.auto_awesome_rounded;
                      label = 'Smart';
                      selected = widget.smartShuffleEnabled;
                      action = widget.onToggleSmartShuffle;
                      break;
                    case 4:
                      icon = widget.loopMode == LoopModeCustom.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded;
                      label = switch (widget.loopMode) {
                        LoopModeCustom.off => 'Repeat',
                        LoopModeCustom.all => 'Repeat semua',
                        LoopModeCustom.one => 'Repeat satu',
                      };
                      selected = widget.loopMode != LoopModeCustom.off;
                      action = widget.onCycleLoopMode;
                      break;
                    case 5:
                      icon = Icons.comment_outlined;
                      label = 'Komentar';
                      action = _loadDiscussion;
                      break;
                    case 6:
                      icon = Icons.lyrics_outlined;
                      label = 'Lirik';
                      action = () => _scrollToLyrics();
                      break;
                    case 7:
                      icon = Icons.picture_in_picture_alt_outlined;
                      label = 'Mini player';
                      action = widget.onPip;
                      break;
                    default:
                      icon = Icons.link_rounded;
                      label = 'Salin link';
                      action = () {
                        unawaited(Clipboard.setData(ClipboardData(text: 'https://youtu.be/${widget.video.videoId}')));
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tautan disalin')));
                      };
                  }
                  final child = FilledButton.tonalIcon(
                    onPressed: action,
                    icon: Icon(icon, size: 17),
                    label: Text(label),
                    style: FilledButton.styleFrom(
                      backgroundColor: selected
                          ? scheme.primary.withValues(alpha: 0.17)
                          : scheme.surfaceContainerLow,
                      foregroundColor: selected
                          ? scheme.primary
                          : scheme.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 38),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  );
                  return child;
                },
              ),
            ),
          ),
          if (description.isNotEmpty)
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [const Icon(Icons.description_outlined, size: 18), const SizedBox(width: 8), const Expanded(child: Text('Deskripsi', style: TextStyle(fontWeight: FontWeight.w900))), Icon(_descriptionExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded)]),
                      const SizedBox(height: 7),
                      Text(description, maxLines: _descriptionExpanded ? null : 3, overflow: _descriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis, style: const TextStyle(height: 1.35, fontSize: 12.5)),
                    ]),
                  ),
                ),
              ),
            ),
          if (widget.playerUiState != null)
            SliverToBoxAdapter(
              child: ValueListenableBuilder<PlayerUiState>(
                valueListenable: widget.playerUiState!,
                builder: (context, state, _) {
                  if (state.video?.videoId != widget.video.videoId || (state.lyrics.isEmpty && !state.lyricsLoading)) return const SizedBox.shrink();
                  return KeyedSubtree(
                    key: _lyricsKey,
                    child: LyricsPanel(lyrics: state.lyrics, loading: state.lyricsLoading, synced: state.lyricsSynced, nativeState: widget.nativeState, onSeek: widget.onSeekFromLyrics ?? (_) async {}),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(child: _discussionTitle(context)),
          if (_liveAvailable && _showLiveChat)
            SliverToBoxAdapter(child: _livePortraitBox(scheme))
          else if (_discussionVisible)
            ..._commentSlivers(scheme)
          else
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: ListTile(
                  leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.forum_outlined, color: scheme.primary, size: 19)),
                  title: const Text('Buka diskusi', style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(_liveAvailable ? 'Lihat komentar atau live chat.' : 'Lihat komentar terbaru dan balasan.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _loadDiscussion,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }

}

