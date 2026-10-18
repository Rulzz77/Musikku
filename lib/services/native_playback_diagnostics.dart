import 'package:flutter/services.dart';

/// Describes an Android output endpoint currently exposed by AudioManager.
/// It is an available-device list, not a guarantee of the route actually in use.
class AudioOutputDevice {
  const AudioOutputDevice({
    required this.id,
    required this.typeCode,
    required this.type,
    required this.productName,
  });

  final int id;
  final int typeCode;
  final String type;
  final String productName;

  String get displayName => productName.trim().isEmpty ? type : productName.trim();

  factory AudioOutputDevice.fromMap(Map<dynamic, dynamic> map) {
    final rawId = map['id'];
    final rawTypeCode = map['typeCode'];
    final rawType = map['type'];
    final rawName = map['productName'];
    return AudioOutputDevice(
      id: rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? -1,
      typeCode: rawTypeCode is num
          ? rawTypeCode.toInt()
          : int.tryParse('$rawTypeCode') ?? 0,
      type: rawType?.toString().trim().isNotEmpty == true
          ? rawType.toString().trim()
          : 'Output audio lain',
      productName: rawName?.toString().trim() ?? '',
    );
  }
}

class AudioOutputSnapshot {
  const AudioOutputSnapshot({
    required this.supported,
    required this.devices,
    this.error,
  });

  final bool supported;
  final List<AudioOutputDevice> devices;
  final String? error;
}

/// Access to native-only playback diagnostics. These calls are local to the
/// Android app and do not send device information or logs over the network.
class NativePlaybackDiagnostics {
  NativePlaybackDiagnostics._();

  static const MethodChannel _channel = MethodChannel('musikku/youtube_player');

  static Future<AudioOutputSnapshot> getAudioOutputs() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getAudioOutputDevices');
      if (raw is! Map) {
        return const AudioOutputSnapshot(
          supported: false,
          devices: <AudioOutputDevice>[],
          error: 'Respons perangkat audio tidak valid.',
        );
      }
      final supported = raw['supported'] == true;
      final rawDevices = raw['devices'];
      final devices = rawDevices is List
          ? rawDevices
              .whereType<Map>()
              .map(AudioOutputDevice.fromMap)
              .toList(growable: false)
          : const <AudioOutputDevice>[];
      return AudioOutputSnapshot(supported: supported, devices: devices);
    } on PlatformException catch (error) {
      return AudioOutputSnapshot(
        supported: false,
        devices: const <AudioOutputDevice>[],
        error: '${error.code}: ${error.message ?? 'Tidak tersedia'}',
      );
    } catch (error) {
      return AudioOutputSnapshot(
        supported: false,
        devices: const <AudioOutputDevice>[],
        error: error.toString(),
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getNativeHealthEvents() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getHealthEvents');
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map((event) {
            final normalized = event.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            return Map<String, dynamic>.from(normalized);
          })
          .toList(growable: false);
    } catch (_) {
      // Flutter-side logs remain available if the native API is unavailable.
      return const <Map<String, dynamic>>[];
    }
  }

  static Future<void> clearNativeHealthEvents() async {
    try {
      await _channel.invokeMethod<void>('clearHealthEvents');
    } catch (_) {
      // Older native builds may not expose this method.
    }
  }
}
