class YoutubePlayerDebugSnapshot {
  final bool ready;
  final String videoId;
  final String state;
  final String preferredQuality;
  final String actualQuality;
  final bool captionsRequested;
  final String captionPreference;
  final int captionTracks;
  final List<String> captionLanguages;
  final String captionSelected;
  final String captionTranslation;
  final bool captionActive;
  final String? error;

  const YoutubePlayerDebugSnapshot({
    this.ready = false,
    this.videoId = '',
    this.state = 'unknown',
    this.preferredQuality = 'default',
    this.actualQuality = 'unknown',
    this.captionsRequested = false,
    this.captionPreference = 'id',
    this.captionTracks = 0,
    this.captionLanguages = const <String>[],
    this.captionSelected = '',
    this.captionTranslation = '',
    this.captionActive = false,
    this.error,
  });

  factory YoutubePlayerDebugSnapshot.fromMap(Map<dynamic, dynamic> raw) {
    final languages = raw['captionLanguages'];
    return YoutubePlayerDebugSnapshot(
      ready: raw['ready'] == true,
      videoId: raw['videoId']?.toString() ?? '',
      state: raw['state']?.toString() ?? 'unknown',
      preferredQuality: raw['preferredQuality']?.toString() ?? 'default',
      actualQuality: raw['actualQuality']?.toString() ??
          raw['currentQuality']?.toString() ??
          'unknown',
      captionsRequested: raw['captionsRequested'] == true,
      captionPreference: raw['captionPreference']?.toString() ?? 'id',
      captionTracks: (raw['captionTracks'] as num?)?.toInt() ?? 0,
      captionLanguages: languages is List
          ? languages.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      captionSelected: raw['captionSelected']?.toString() ?? '',
      captionTranslation: raw['captionTranslation']?.toString() ?? '',
      captionActive: raw['captionActive'] == true,
      error: raw['error']?.toString(),
    );
  }

  bool get hasError => error != null && error!.isNotEmpty;

  String get captionModeLabel {
    switch (captionPreference) {
      case 'original':
        return 'Bahasa asli';
      case 'auto:id':
        return 'Terjemahan otomatis Indonesia';
      case 'auto:en':
        return 'Terjemahan otomatis Inggris';
      case 'id':
        return 'Indonesia';
      case 'en':
        return 'Inggris';
      default:
        return captionPreference;
    }
  }

  String get stateLabel {
    switch (state) {
      case 'playing':
        return 'Playing';
      case 'paused':
        return 'Paused';
      case 'buffering':
        return 'Buffering';
      case 'ended':
        return 'Ended';
      case 'cued':
        return 'Cued';
      case 'unstarted':
        return 'Unstarted';
      case 'error':
        return 'Error';
      default:
        return state;
    }
  }
}
