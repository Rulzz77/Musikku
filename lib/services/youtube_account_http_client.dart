import 'dart:convert';

import 'package:http/http.dart' as http;

import 'youtube_api_request_guard.dart';


typedef YoutubeAccountAccessTokenProvider = Future<String> Function({
  required bool write,
});

Future<http.Response> _guardedGet(
  Uri uri, {
  Map<String, String>? headers,
}) async {
  await YoutubeApiRequestGuard.beforeRequest('data');
  final response = await http.get(uri, headers: headers)
      .timeout(const Duration(seconds: 12));
  YoutubeApiRequestGuard.observeResponse(
    scope: 'data',
    statusCode: response.statusCode,
    body: response.body,
    headers: response.headers,
  );
  return response;
}

Future<http.Response> _guardedPost(
  Uri uri, {
  required Map<String, String> headers,
  required String body,
}) async {
  await YoutubeApiRequestGuard.beforeRequest('data');
  final response = await http.post(uri, headers: headers, body: body)
      .timeout(const Duration(seconds: 12));
  YoutubeApiRequestGuard.observeResponse(
    scope: 'data',
    statusCode: response.statusCode,
    body: response.body,
    headers: response.headers,
  );
  return response;
}

Future<http.Response> _guardedDelete(
  Uri uri, {
  required Map<String, String> headers,
}) async {
  await YoutubeApiRequestGuard.beforeRequest('data');
  final response = await http.delete(uri, headers: headers)
      .timeout(const Duration(seconds: 12));
  YoutubeApiRequestGuard.observeResponse(
    scope: 'data',
    statusCode: response.statusCode,
    body: response.body,
    headers: response.headers,
  );
  return response;
}

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
      final response = await _guardedGet(uri);
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
    final response = await _guardedGet(uri, headers: {'Authorization': 'Bearer $token'});
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
    final response = await _guardedPost(
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
    final response = await _guardedDelete(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('YouTube API ${response.statusCode}: ${response.body}');
    }
  }
}
