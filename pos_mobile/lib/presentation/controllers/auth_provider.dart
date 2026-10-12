import 'package:flutter/foundation.dart';
import '../../data/datasources/auth_api_source.dart';

class AuthUser {
  final String id;
  final String name;
  final String role;

  const AuthUser({
    required this.id,
    required this.name,
    required this.role,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
      );
}

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required AuthApiSource api,
    required ValueChanged<String?> onTokenChanged,
  })  : _api = api,
        _onTokenChanged = onTokenChanged;

  final AuthApiSource _api;
  final ValueChanged<String?> _onTokenChanged;
  bool isInitialized = false;
  bool needsSetup = false;
  bool needsPinSetup = false;
  bool bootstrapAvailable = false;
  bool isLoading = false;
  String? error;
  String? token;
  AuthUser? user;
  bool get isAdminLoggedIn => token != null && user?.role == 'ADMIN';
  Future<void>? _initialization;
  Future<void>? _cashierSession;
  bool _hasCashierSession = false;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final response = await _api.status();
      needsSetup = response['needsSetup'] == true;
      needsPinSetup = response['needsPinSetup'] == true;
      bootstrapAvailable = response['bootstrapAvailable'] == true;
      error = null;
    } catch (exception) {
      error = exception.toString();
    }
    try {
      await ensureCashierSession();
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    }
    isInitialized = true;
    notifyListeners();
  }

  Future<void> ensureCashierSession() async {
    if (_hasCashierSession && token != null) return;
    _cashierSession ??= _createCashierSession();
    try {
      await _cashierSession;
    } finally {
      _cashierSession = null;
    }
  }

  Future<void> _createCashierSession() async {
    final response = await _api.createCashierSession();
    token = response['token'] as String;
    user = null;
    _hasCashierSession = true;
    _onTokenChanged(token);
  }

  Future<bool> loginWithPin(String pin, {required String expectedRole}) =>
      _authenticate(
        () => _api.loginWithPin(pin, expectedRole),
        expectedRole: expectedRole,
      );

  Future<bool> setupAdminWithPin(
    String name,
    String pin,
    String bootstrapToken,
  ) =>
      _authenticate(
        () => _api.bootstrapAdminWithPin(name, pin, bootstrapToken),
        expectedRole: 'ADMIN',
      );

  Future<bool> changeAdminPin(String currentPin, String newPin) async {
    final currentToken = token;
    if (currentToken == null) {
      error = 'Sesi login tidak ditemukan.';
      notifyListeners();
      return false;
    }
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await _api.changePin(currentPin, newPin, currentToken);
      return true;
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _authenticate(
    Future<Map<String, dynamic>> Function() request, {
    String? expectedRole,
  }) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final response = await request();
      final authenticatedUser =
          AuthUser.fromJson(response['user'] as Map<String, dynamic>);
      final roleMatches = expectedRole == null ||
          authenticatedUser.role == expectedRole ||
          (expectedRole == 'ADMIN' && authenticatedUser.role == 'OWNER');
      if (!roleMatches) {
        error = expectedRole == 'ADMIN'
            ? 'Akun ini bukan akun admin.'
            : 'Akun ini bukan akun kasir.';
        return false;
      }
      token = response['token'] as String;
      user = authenticatedUser;
      _hasCashierSession = false;
      _onTokenChanged(token);
      needsSetup = false;
      needsPinSetup = false;
      return true;
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final currentToken = token;
    token = null;
    user = null;
    _hasCashierSession = false;
    _onTokenChanged(null);
    notifyListeners();
    if (currentToken != null) {
      try {
        await _api.logout(currentToken);
      } catch (_) {
        // The local session is cleared even when the server is unreachable.
      }
    }
    try {
      await ensureCashierSession();
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }
}
