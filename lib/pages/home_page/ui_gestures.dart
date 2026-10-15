part of '../home_page.dart';

/// Gestur aplikasi yang tidak mengambil alih kontrol media YouTube.
/// Tap, seek, playback, dan menu kualitas diproses oleh pemutar YouTube.
extension _HomeYoutubeGestures on _HomePageState {
  void _onYoutubePointerDown(PointerDownEvent event) {
    if (!mounted || _youtubeWatchVideo == null || _youtubeSystemPipMode) return;
    _youtubePointerDragStarted = false;
    _youtubePointerTotalDy = 0.0;
    _youtubePointerTotalDx = 0.0;
    // Reserve swipe-to-mini-player for the upper video area. YouTube's native
    // timeline/settings dropdown lives near the bottom and must keep gestures.
    final size = MediaQuery.sizeOf(context);
    final isLandscapeNow = size.width > size.height;
    final playerHeight = isLandscapeNow ? size.height : size.width * 9 / 16;
    _youtubePointerStartedInDragZone = !isLandscapeNow &&
        event.localPosition.dy <= playerHeight * 0.52;
  }

  void _onYoutubePointerMove(PointerMoveEvent event) {
    if (!mounted || _youtubeWatchVideo == null || _youtubeSystemPipMode ||
        !_youtubePointerStartedInDragZone) return;

    _youtubePointerTotalDy += event.delta.dy;
    _youtubePointerTotalDx += event.delta.dx;

    final isLandscapeNow = MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    if (isLandscapeNow || _youtubePointerDragStarted) {
      if (_youtubePointerDragStarted && !isLandscapeNow) {
        _handlePortraitSwipeDrag(event.delta.dy);
      }
      return;
    }

    final mostlyVertical = _youtubePointerTotalDy.abs() > _youtubePointerTotalDx.abs();
    if (mostlyVertical && _youtubePointerTotalDy.abs() >= 8.0) {
      _youtubePointerDragStarted = true;
      _handlePortraitSwipeDrag(event.delta.dy);
    }
  }

  void _onYoutubePointerUp(PointerUpEvent event) {
    if (!mounted || _youtubeWatchVideo == null || _youtubeSystemPipMode) return;

    _youtubePointerStartedInDragZone = false;
    if (_youtubePointerDragStarted) {
      _youtubePointerDragStarted = false;
      _youtubePointerTotalDy = 0.0;
      _youtubePointerTotalDx = 0.0;
      _finishPortraitSwipe();
      return;
    }

    // Sentuhan biasa tetap ditangani pemutar YouTube yang tertanam.
    _youtubePointerTotalDy = 0.0;
    _youtubePointerTotalDx = 0.0;
  }

  void _onYoutubePointerCancel(PointerCancelEvent event) {
    if (!mounted) return;
    _youtubePointerDragStarted = false;
    _youtubePointerStartedInDragZone = false;
    _youtubePointerTotalDy = 0.0;
    _youtubePointerTotalDx = 0.0;
    _cancelPortraitSwipe();
  }

  void _handlePortraitSwipeDrag(double dy) {
    final size = MediaQuery.sizeOf(context);
    final isLandscapeNow = size.width > size.height;
    if (!mounted || _youtubeWatchVideo == null || isLandscapeNow) return;

    _youtubePortraitSwipeDragging = true;
    final next = _youtubePortraitSwipeDy + dy;
    // Sedikit resistensi setelah titik nyaman agar tarikan tetap terasa halus.
    final adjusted = next > 220.0
        ? 220.0 + ((next - 220.0) * 0.16)
        : next;
    _youtubePortraitSwipeDy = adjusted.clamp(0.0, 250.0).toDouble();
  }

  void _finishPortraitSwipe() {
    if (!mounted || _youtubeWatchVideo == null) return;

    final shouldOpenPip = _youtubePortraitSwipeDy >= 132.0;
    _youtubePortraitSwipeDragging = false;

    if (shouldOpenPip) {
      _youtubePortraitSwipeDy = 0.0;
      _updateHomeState(() {});
      unawaited(_enterFloatingPip());
      return;
    }

    _youtubePortraitSwipeDy = 0.0;
    _updateHomeState(() {});
  }

  void _cancelPortraitSwipe() {
    if (!mounted) return;
    _youtubePortraitSwipeDragging = false;
    _youtubePortraitSwipeDy = 0.0;
    _updateHomeState(() {});
  }
}
