import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One conversational turn sent to the Blossom backend.
class ChatApiMessage {
  const ChatApiMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class ChatApiException implements Exception {
  const ChatApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calls the app's own backend. Provider credentials and health instructions
/// belong on that server, never in this Flutter application.
class BlossomChatApi {
  BlossomChatApi({http.Client? client}) : _client = client ?? http.Client();

  static const String _baseUrl = String.fromEnvironment('CHAT_API_BASE_URL');
  final http.Client _client;

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  Future<String> sendMessage(List<ChatApiMessage> messages) async {
    if (!isConfigured) {
      throw const ChatApiException(
        'No chat backend is configured. Add CHAT_API_BASE_URL when you run the app, then restart it.',
      );
    }

    final baseUri = Uri.tryParse(_baseUrl.trim());
    if (baseUri == null || !baseUri.hasAuthority) {
      throw const ChatApiException(
        'The chat backend URL is invalid. Check CHAT_API_BASE_URL and try again.',
      );
    }

    final isLocalDevelopmentHost = const {
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
      '::1',
    }.contains(baseUri.host);
    if (baseUri.scheme != 'https' &&
        !(baseUri.scheme == 'http' && isLocalDevelopmentHost)) {
      throw const ChatApiException(
        'Use an HTTPS URL for the chat backend. Plain HTTP is allowed only for local development.',
      );
    }

    final base = _baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final endpoint = Uri.tryParse('$base/v1/chat');
    if (endpoint == null) {
      throw const ChatApiException(
        'The chat backend URL is invalid. Check CHAT_API_BASE_URL and try again.',
      );
    }

    late final http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'messages': messages.map((message) => message.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 35));
    } on TimeoutException {
      throw const ChatApiException(
        'The chat service took too long to respond. Please try again.',
      );
    } on http.ClientException {
      throw const ChatApiException(
        'I couldn’t reach the chat service. Check your connection and backend URL.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatApiException(
        'The chat service returned an error (${response.statusCode}). Please try again later.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final reply = decoded['reply'];
        if (reply is String && reply.trim().isNotEmpty) return reply.trim();
      }
    } on FormatException {
      // Report one stable client-facing message for invalid backend responses.
    }

    throw const ChatApiException(
      'The chat service returned an unexpected response. Check its /v1/chat setup.',
    );
  }

  void close() => _client.close();
}
