import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pos_mobile/data/datasources/auth_api_source.dart';
import 'package:pos_mobile/domain/entities/order_entity.dart';
import 'package:pos_mobile/domain/entities/product_entity.dart';
import 'package:pos_mobile/domain/repositories/pos_repository.dart';
import 'package:pos_mobile/domain/usecases/process_checkout.dart';
import 'package:pos_mobile/presentation/controllers/auth_provider.dart';
import 'package:pos_mobile/presentation/controllers/pos_provider.dart';
import 'package:pos_mobile/presentation/pages/admin_dashboard_page.dart';
import 'package:pos_mobile/presentation/pages/auth_gate.dart';
import 'package:pos_mobile/presentation/pages/pos_dashboard_page.dart';

class _FakeAuthApiSource extends AuthApiSource {
  _FakeAuthApiSource({this.needsSetup = true});

  final bool needsSetup;

  @override
  Future<Map<String, dynamic>> createCashierSession() async =>
      {'token': 'cashier-token'};

  @override
  Future<Map<String, dynamic>> status() async => {
        'needsSetup': needsSetup,
        'needsPinSetup': needsSetup,
        'bootstrapAvailable': true,
      };

  @override
  Future<Map<String, dynamic>> loginWithPin(String pin, String role) async => {
        'token': 'demo-token',
        'user': {'id': '1', 'name': 'User', 'role': role},
      };

  @override
  Future<Map<String, dynamic>> bootstrapAdminWithPin(
          String name, String pin, String bootstrapToken) async =>
      {
        'token': 'demo-token',
        'user': {'id': '1', 'name': name, 'role': 'ADMIN'},
      };

  @override
  Future<void> changePin(
      String currentPin, String newPin, String token) async {}

  @override
  Future<void> logout(String token) async {}
}

class _FakePosRepository implements PosRepository {
  @override
  bool get isUsingCachedProducts => false;

  @override
  Future<List<ProductEntity>> getProducts() async => [];

  @override
  Future<List<OrderEntity>> getPendingOrders() async => [];

  @override
  Future<bool> saveOrder(OrderEntity order) async => true;

  @override
  Future<void> syncPendingOrders() async {}
}

Widget _testApp(AuthProvider auth) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(
          create: (_) => PosProvider(
              processCheckoutUseCase: ProcessCheckoutUseCase(
            _FakePosRepository(),
          )),
        ),
      ],
      child: const MaterialApp(home: AuthGate()),
    );

void main() {
  testWidgets('auth gate opens POS directly without a cashier PIN',
      (tester) async {
    final auth = AuthProvider(
      api: _FakeAuthApiSource(),
      onTokenChanged: (_) {},
    );

    await tester.pumpWidget(_testApp(auth));
    await tester.pumpAndSettle();

    expect(find.byType(PosDashboardPage), findsOneWidget);
    expect(find.text('Masuk Back-Office'), findsNothing);
    expect(auth.token, 'cashier-token');
    expect(auth.user, isNull);
  });

  testWidgets('admin button beside stock opens PIN-protected admin login',
      (tester) async {
    final auth = AuthProvider(
      api: _FakeAuthApiSource(needsSetup: false),
      onTokenChanged: (_) {},
    );

    await tester.pumpWidget(_testApp(auth));
    await tester.pumpAndSettle();

    expect(find.byType(PosDashboardPage), findsOneWidget);
    expect(find.byTooltip('Stok bahan'), findsOneWidget);
    expect(find.byTooltip('Admin'), findsOneWidget);
    await tester.tap(find.byTooltip('Admin'));
    await tester.pumpAndSettle();

    expect(find.text('PIN admin 6 digit'), findsOneWidget);
    expect(find.text('Token bootstrap server'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Kata sandi'), findsNothing);
  });

  test('auth provider can update admin pin', () async {
    final auth = AuthProvider(
      api: _FakeAuthApiSource(),
      onTokenChanged: (_) {},
    );
    auth.user = const AuthUser(
      id: '1',
      name: 'Owner',
      role: 'OWNER',
    );
    auth.token = 'demo-token';

    final success = await auth.changeAdminPin('123456', '654321');

    expect(success, isTrue);
  });

  testWidgets('auth gate routes authenticated admin to dashboard',
      (tester) async {
    final auth = AuthProvider(
      api: _FakeAuthApiSource(),
      onTokenChanged: (_) {},
    );
    auth.isInitialized = true;
    auth.needsSetup = false;
    auth.needsPinSetup = false;
    auth.user = const AuthUser(
      id: '1',
      name: 'Owner',
      role: 'OWNER',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: const MaterialApp(home: AuthGate()),
      ),
    );

    expect(find.byType(AdminDashboardPage), findsOneWidget);
  });
}
