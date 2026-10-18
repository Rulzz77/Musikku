import 'dart:convert';

import 'package:http/http.dart' as http;

typedef YoutubeAccountAccessTokenProvider = Future<String> Function({
  required bool write,
});

/// HTTP boundary for authenticated and public YouTube account endpoints.
/// Session lifecycle remains in YoutubeAccountService.
class YoutubeAccountHttpClient {
  const YoutubeAccountHttpClient({
    required this.apiKey,
    required this.baseUrl,
    required this.isSignedIn,
    required this.accessToken,
  });

  final String apiKey;
  final String baseUrl;
  final bool Function() isSignedIn;
  final YoutubeAccountAccessTokenProvider accessToken;

  Future<Map<String, dynamic>> get(
    String path,
    Map<String, String> params, {
    required bool write,
  }) async {
    // Endpoint mine=true wajib login. Data publik boleh memakai API key.
    final isPrivate = params['mine'] == 'true';

    Future<Map<String, dynamic>> publicGet() async {
      final uri = Uri.parse('$baseUrl/$path').replace(
        queryParameters: <String, String>{...params, 'key': apiKey},
      );
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('YouTube API ${response.statusCode}: ${response.body}');
      }
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }

    if (!isPrivate && apiKey.isNotEmpty && !isSignedIn()) {
      return publicGet();
    }

    final String token;
    try {
      token = await accessToken(write: write);
    } catch (_) {
      if (!isPrivate && apiKey.isNotEmpty) return publicGet();
      rethrow;
    }
    final uri = Uri.parse('$baseUrl/$path').replace(queryParameters: params);
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('YouTube API ${response.statusCode}: ${response.body}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    required bool write,
  }) async {
    final token = await accessToken(write: write);
    final response = await http.post(
      Uri.parse('$baseUrl/$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('YouTube API ${response.statusCode}: ${response.body}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<void> delete(
    String path,
    Map<String, String> params, {
    required bool write,
  }) async {
    final token = await accessToken(write: write);
    final uri = Uri.parse('$baseUrl/$path').replace(queryParameters: params);
    final response = await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('YouTube API ${response.statusCode}: ${response.body}');
    }
  }
}
