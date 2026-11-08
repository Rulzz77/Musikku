import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Official YouTube iFrame surface used on iOS. Playback follows YouTube's
/// player rules and cannot provide the Android-only NewPipe audio mode.
class IOSYoutubePlayerSurface extends StatelessWidget {
  const IOSYoutubePlayerSurface({super.key, required this.controller});

  final YoutubePlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: YoutubePlayer(
        controller: controller,
        aspectRatio: 16 / 9,
        keepAlive: true,
      ),
    );
  }
}
