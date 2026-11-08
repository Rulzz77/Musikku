import 'loop_mode.dart';
import 'lyric.dart';
import 'youtube_search_result.dart';

class PlayerUiState {
  final YoutubeSearchResult? video;
  final List<LyricLine> lyrics;
  final bool lyricsLoading;
  final bool lyricsSynced;
  final bool isShuffle;
  final bool isSmartShuffle;
  final LoopModeCustom loopMode;
  final bool isFavorite;
  final bool isLiked;
  final bool isDisliked;

  const PlayerUiState({
    this.video,
    this.lyrics = const [],
    this.lyricsLoading = false,
    this.lyricsSynced = false,
    this.isShuffle = false,
    this.isSmartShuffle = false,
    this.loopMode = LoopModeCustom.off,
    this.isFavorite = false,
    this.isLiked = false,
    this.isDisliked = false,
  });

  PlayerUiState copyWith({
    YoutubeSearchResult? video,
    List<LyricLine>? lyrics,
    bool? lyricsLoading,
    bool? lyricsSynced,
    bool? isShuffle,
    bool? isSmartShuffle,
    LoopModeCustom? loopMode,
    bool? isFavorite,
    bool? isLiked,
    bool? isDisliked,
  }) {
    return PlayerUiState(
      video: video ?? this.video,
      lyrics: lyrics ?? this.lyrics,
      lyricsLoading: lyricsLoading ?? this.lyricsLoading,
      lyricsSynced: lyricsSynced ?? this.lyricsSynced,
      isShuffle: isShuffle ?? this.isShuffle,
      isSmartShuffle: isSmartShuffle ?? this.isSmartShuffle,
      loopMode: loopMode ?? this.loopMode,
      isFavorite: isFavorite ?? this.isFavorite,
      isLiked: isLiked ?? this.isLiked,
      isDisliked: isDisliked ?? this.isDisliked,
    );
  }
}
