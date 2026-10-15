import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Surface WebView-YouTube yang mempertahankan struktur element yang identik
/// di portrait, landscape, dan PiP agar AndroidView/PlatformView tidak dibuat
/// ulang saat ukuran berubah.
class HiddenYoutubePlayer extends StatelessWidget {
  final bool visible;
  final bool interactive;
  final double? width;
  final double? height;

  const HiddenYoutubePlayer({
    super.key,
    this.visible = false,
    this.interactive = false,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackWidth = MediaQuery.sizeOf(context).width;
    final effectiveWidth = width ?? fallbackWidth;
    final effectiveHeight = height ?? (effectiveWidth * 9 / 16);

    // JANGAN mengubah susunan widget ini antar mode.
    // Yang berubah hanya ukuran child-nya. Dengan begitu element AndroidView
    // tetap pada slot Flutter yang sama ketika rotasi terjadi.
    return SizedBox.expand(
      child: IgnorePointer(
        ignoring: !interactive,
        child: Opacity(
          opacity: visible ? 1.0 : 0.01,
          child: ColoredBox(
            color: Colors.black,
            child: Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: effectiveWidth,
                height: effectiveHeight,
                child: AndroidView(
                  key: const ValueKey<String>('musikku-youtube-platform-view'),
                  viewType: 'musikku/youtube_player',
                  // Hand native gestures to YouTube so taps on Settings,
                  // quality options, seek bar, and playback buttons work.
                  // Raw Listener above this widget still observes pointer
                  // positions used for the app's swipe-to-mini-player gesture.
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
