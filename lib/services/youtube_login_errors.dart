import 'package:flutter/services.dart';

/// Mengubah error login/izin menjadi pesan yang bisa ditindaklanjuti.
String describeLoginError(Object e) {
  if (e is StateError) {
    if (e.message == 'YOUTUBE_AUTH_REQUIRED') {
      return 'Izin YouTube belum disetujui. Tekan "Izinkan" atau login ulang.';
    }
    return e.message;
  }
  // google_sign_in 6.3 exposes native sign-in failures as PlatformException;
  // The newer 7.x exception type is not part of this dependency version.
  if (e is PlatformException) {
    final code = e.code;
    final detail = (e.message ?? '').trim();
    if (code == 'sign_in_canceled' || code == 'sign_in_cancelled' || code == 'canceled') {
      return 'Login dibatalkan atau ditolak Google.'
          '${detail.isEmpty ? '' : ' ($detail)'}';
    }
    if (code == 'sign_in_failed' || code == 'sign_in_required' || code == '10') {
      return 'Login Google gagal ($code). Cek SHA-1, package '
          'com.musikku.app, Web Client ID, dan konfigurasi OAuth.'
          '${detail.isEmpty ? '' : ' ($detail)'}';
    }
    return 'Login gagal ($code).${detail.isEmpty ? '' : ' $detail'}';
  }
  final text = e.toString();
  return 'Gagal: ${text.length > 180 ? '${text.substring(0, 180)}…' : text}';
}
