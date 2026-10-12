import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthApiSource {
  AuthApiSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _baseUrl = String.fromEnvironment(
    'POS_API_URL',
    defaultValue: 'http://127.0.0.1:3000/api/v1',
  );

  Future<Map<String, dynamic>> status() => _send('GET', '/auth/status');

  Future<Map<String, dynamic>> createCashierSession() =>
      _send('POST', '/auth/cashier-session', body: {});

  Future<Map<String, dynamic>> loginWithPin(String pin, String role) =>
      _send('POST', '/auth/login-pin', body: {'pin': pin, 'role': role});

  Future<Map<String, dynamic>> bootstrapAdminWithPin(
    String name,
    String pin,
    String bootstrapToken,
  ) =>
      _send('POST', '/auth/bootstrap-pin', body: {
        'name': name,
        'pin': pin,
        'bootstrapToken': bootstrapToken,
      });

  Future<void> changePin(String currentPin, String newPin, String token) async {
    await _send('PUT', '/auth/pin',
        body: {'currentPin': currentPin, 'newPin': newPin}, token: token);
  }

  Future<void> logout(String token) async {
    await _send('POST', '/auth/logout', token: token);
  }

  Future<Map<String, dynamic>> _send(String method, String path,
      {Map<String, dynamic>? body, String? token}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final response = switch (method) {
      'GET' => await _client.get(uri, headers: headers),
      'POST' =>
        await _client.post(uri, headers: headers, body: jsonEncode(body)),
      'PUT' => await _client.put(uri, headers: headers, body: jsonEncode(body)),
      _ => throw UnsupportedError('Metode HTTP tidak didukung.'),
    };
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['message'] ?? 'Permintaan gagal.');
    }
    return decoded;
  }
}
