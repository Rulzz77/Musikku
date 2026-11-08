import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android launcher-icon switcher. Each variant uses the same MusikKu artwork;
/// only the background palette changes. Other platforms keep their default icon.
class AppIconService {
  AppIconService._();

  static const MethodChannel _channel = MethodChannel('musikku/app_icon');

  static Future<bool> setLauncherIcon(String variant) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    const supported = <String>{
      'blue', 'black', 'purple', 'green', 'pink', 'orange', 'teal', 'silver',
    };
    if (!supported.contains(variant)) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'setLauncherIcon',
            <String, Object>{'variant': variant},
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
