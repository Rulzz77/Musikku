import 'dart:async';

import 'package:flutter/services.dart';

/// Native Media3 audio features. The PCM stream is produced from the decoded
/// samples in MusikKu's own ExoPlayer path, never from the microphone.
class NativeAudioFeatures {
  NativeAudioFeatures._();

  static const MethodChannel _methods = MethodChannel('musikku/audio_features');
  static const EventChannel _events = EventChannel('musikku/audio_visualizer/events');

  static Stream<List<double>> get waveform => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) {
        final map = event as Map;
        final rawBars = map['bars'];
        if (rawBars is! List) return const <double>[];
        return rawBars
            .whereType<num>()
            .map((value) => (value.toDouble() / 100).clamp(0.0, 1.0))
            .toList(growable: false);
      });

  static Future<Map<String, dynamic>> setVisualizerEnabled(bool enabled) async {
    try {
      final raw = await _methods.invokeMapMethod<String, dynamic>(
        'setVisualizerEnabled',
        <String, dynamic>{'enabled': enabled},
      );
      return raw ?? const <String, dynamic>{'enabled': false};
    } on PlatformException catch (error) {
      return <String, dynamic>{'enabled': false, 'error': error.message ?? error.code};
    } catch (error) {
      return <String, dynamic>{'enabled': false, 'error': error.toString()};
    }
  }

  static Future<bool> setLoudnessNormalization(bool enabled) async {
    try {
      return await _methods.invokeMethod<bool>(
            'setLoudnessNormalization',
            <String, dynamic>{'enabled': enabled},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
