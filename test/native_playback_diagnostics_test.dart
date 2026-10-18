import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/native_playback_diagnostics.dart';

void main() {
  group('AudioOutputDevice', () {
    test('parses native route map and shows friendly product name', () {
      final device = AudioOutputDevice.fromMap(<String, Object>{
        'id': 7,
        'typeCode': 8,
        'type': 'Bluetooth audio',
        'productName': 'Wireless Headphones',
      });

      expect(device.id, 7);
      expect(device.typeCode, 8);
      expect(device.type, 'Bluetooth audio');
      expect(device.displayName, 'Wireless Headphones');
    });

    test('uses type when the native device name is empty', () {
      final device = AudioOutputDevice.fromMap(<String, Object>{
        'id': '2',
        'typeCode': '2',
        'type': 'Speaker bawaan',
        'productName': '  ',
      });

      expect(device.id, 2);
      expect(device.displayName, 'Speaker bawaan');
    });

    test('handles partial native maps without throwing', () {
      final device = AudioOutputDevice.fromMap(<String, Object?>{});

      expect(device.id, -1);
      expect(device.typeCode, 0);
      expect(device.type, 'Output audio lain');
      expect(device.displayName, 'Output audio lain');
    });
  });
}
