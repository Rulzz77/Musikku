import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FloatingLyricsBridge {
  FloatingLyricsBridge._();

  static const MethodChannel _channel = MethodChannel('musikku/floating_lyrics');
  static const String _enabledKey = 'floating_lyrics_enabled_v1';
  static bool _initialized = false;
  static bool _enabled = false;
  static String _lastText = '';

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? false;
      if (_enabled) {
        final allowed = await canDrawOverlays();
        if (allowed) {
          await _channel.invokeMethod<bool>('setEnabled', <String, dynamic>{'enabled': true});
        } else {
          _enabled = false;
          await prefs.setBool(_enabledKey, false);
        }
      }
    } catch (_) {
      _enabled = false;
    }
  }

  static bool get enabled => _enabled;

  static Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns false when permission is missing or the platform is unsupported.
  static Future<bool> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return false;
    try {
      if (enabled && !await canDrawOverlays()) {
        await _channel.invokeMethod<void>('requestOverlayPermission');
        return false;
      }
      final result = await _channel.invokeMethod<bool>(
            'setEnabled',
            <String, dynamic>{'enabled': enabled},
          ) ??
          false;
      if (!result && enabled) return false;
      _enabled = enabled;
      _lastText = '';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> updateLine(String text) async {
    if (!Platform.isAndroid || !_enabled) return;
    final safe = text.trim();
    if (safe.isEmpty || safe == _lastText) return;
    _lastText = safe;
    try {
      await _channel.invokeMethod<void>('updateText', <String, dynamic>{'text': safe});
    } catch (_) {
      // Overlay may have been closed by the system or user.
    }
  }
}
