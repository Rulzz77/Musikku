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

  /// Reads the device's native Dolby codec and Android Spatializer capabilities.
  /// This reports compatibility only; it does not prove that the current source
  /// contains Atmos metadata or that an OEM Dolby effect is enabled.
  static Future<Map<String, dynamic>> getDolbyAtmosCapabilities() async {
    try {
      final raw = await _methods.invokeMapMethod<String, dynamic>(
        'getDolbyAtmosCapabilities',
      );
      return raw ?? const <String, dynamic>{'available': false};
    } on PlatformException catch (error) {
      return <String, dynamic>{
        'available': false,
        'error': error.message ?? error.code,
      };
    } catch (error) {
      return <String, dynamic>{'available': false, 'error': error.toString()};
    }
  }

  /// Opens Android sound settings so the user can enable an OEM Dolby mode,
  /// if the device manufacturer exposes one.
  static Future<bool> openSystemSoundSettings() async {
    try {
      return await _methods.invokeMethod<bool>('openSystemSoundSettings') ?? false;
    } catch (_) {
      return false;
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

  /// Returns live PCM diagnostics from Media3. Unlike the toggle result,
  /// this confirms whether buffers have actually passed through the DSP.
  static Future<Map<String, dynamic>> getSpeakerSoundstageStatus() async {
    try {
      final raw = await _methods.invokeMapMethod<String, dynamic>(
        'getSpeakerSoundstageStatus',
      );
      return raw ?? const <String, dynamic>{'serviceAttached': false};
    } on PlatformException catch (error) {
      return <String, dynamic>{
        'serviceAttached': false,
        'error': error.message ?? error.code,
      };
    } catch (error) {
      return <String, dynamic>{
        'serviceAttached': false,
        'error': error.toString(),
      };
    }
  }

  /// Enables the mono-safe psychoacoustic DSP in MusikKu's Media3 PCM chain.
  /// This is an original MusikKu effect, not Dolby Atmos or Dolby decoding.
  static Future<Map<String, dynamic>> setSpeakerSoundstage({
    required bool enabled,
    int strength = 85,
  }) async {
    try {
      final result = await _methods.invokeMapMethod<String, dynamic>(
        'setSpeakerSoundstage',
        <String, dynamic>{
          'enabled': enabled,
          'strength': strength.clamp(0, 100),
        },
      );
      return result ?? const <String, dynamic>{'saved': false};
    } on PlatformException catch (error) {
      return <String, dynamic>{
        'saved': false,
        'error': error.message ?? error.code,
      };
    } catch (error) {
      return <String, dynamic>{'saved': false, 'error': error.toString()};
    }
  }
}
