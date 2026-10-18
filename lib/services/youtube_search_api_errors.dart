import 'dart:convert';

import 'package:http/http.dart' as http;

/// Stateless interpretation of YouTube API errors for search requests.
class YoutubeSearchApiErrors {
  const YoutubeSearchApiErrors();

  String errorReason(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final error = body is Map && body['error'] is Map
          ? body['error'] as Map
          : null;
      final errors = error?['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        return (errors.first as Map)['reason']?.toString() ?? '';
      }
      return error?['status']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  String errorMessage(http.Response response) {
    final reason = errorReason(response);

    if (reason == 'quotaExceeded' || reason == 'dailyLimitExceeded') {
      return 'Kuota YouTube API hari ini sudah habis. Coba lagi besok.';
    }

    if (response.statusCode == 429) {
      return 'YouTube sedang membatasi permintaan sementara. Coba lagi beberapa saat.';
    }

    if (reason == 'keyInvalid' || reason == 'forbidden') {
      return 'API key YouTube tidak valid atau dibatasi. Cek pengaturan key.';
    }

    return 'Gagal mencari lagu (kode ${response.statusCode}).';
  }
}
