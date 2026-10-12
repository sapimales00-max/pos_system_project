import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pos_mobile/data/datasources/local_db_source.dart';
import 'package:pos_mobile/data/datasources/remote_api_source.dart';
import 'package:pos_mobile/data/repositories/pos_repository_impl.dart';
import 'package:pos_mobile/domain/entities/order_entity.dart';
import 'package:pos_mobile/domain/entities/product_entity.dart';
import 'package:pos_mobile/domain/repositories/pos_repository.dart';
import 'package:pos_mobile/domain/usecases/process_checkout.dart';
import 'package:pos_mobile/presentation/controllers/pos_provider.dart';
import 'package:pos_mobile/presentation/pages/admin_modules.dart';
import 'package:pos_mobile/presentation/pages/pos_dashboard_page.dart';

class _FakePosRepository implements PosRepository {
  OrderEntity? savedOrder;
  final List<OrderEntity> pendingOrders = [];
  int syncCalls = 0;

  @override
  bool get isUsingCachedProducts => false;

  @override
  Future<List<ProductEntity>> getProducts() async => [];

  @override
  Future<List<OrderEntity>> getPendingOrders() async =>
      List.unmodifiable(pendingOrders);

  @override
  Future<bool> saveOrder(OrderEntity order) async {
    savedOrder = order;
    return true;
  }

  @override
  Future<void> syncPendingOrders() async {
    syncCalls++;
    pendingOrders.clear();
  }
}

class _OfflineThenOnlineApi extends RemoteApiSource {
  bool isOnline = false;
  int syncAttempts = 0;
  late List<ProductEntity> remoteProducts;

  @override
  Future<List<ProductEntity>> getProducts() async {
    if (!isOnline) throw const RemoteApiException(503, 'Server offline');
    return remoteProducts;
  }

  @override
  Future<void> syncOrder(OrderEntity order) async {
    syncAttempts++;
    if (!isOnline) throw const RemoteApiException(503, 'Server offline');
  }
}

void main() {
  test('financial report PDF contains a valid document signature', () async {
    final document = buildFinancialReportPdfDocument(
      report: {
        'sales_total': 100000,
        'cost_total': 40000,
        'gross_profit': 60000,
        'expense_total': 10000,
        'net_profit': 50000,
        'transaction_count': 2,
      },
      products: [
        {
          'name': 'Kopi Susu',
          'category': 'Coffee',
          'quantity': 2,
          'revenue': 100000,
          'cost': 40000,
          'gross_profit': 60000,
        },
      ],
      expenses: [
        {
          'expense_date': '2026-10-03',
          'category': 'Listrik',
          'description': 'Tagihan listrik',
          'amount': 10000,
        },
      ],
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 3),
    );

    final bytes = await document.save();
    expect(bytes.take(5), [37, 80, 68, 70, 45]);
  });

  late _FakePosRepository repository;
  late PosProvider provider;
  late ProductEntity product;

  setUp(() {
    repository = _FakePosRepository();
    provider =
        PosProvider(processCheckoutUseCase: ProcessCheckoutUseCase(repository));
    product = ProductEntity(
      id: 'test-product',
      name: 'Test item',
      category: 'Test',
      price: 30000,
      stock: 2,
      imageUrl: '',
    );
    provider.loadProducts([product]);
  });

  test('repository returns cached products when remote server is offline',
      () async {
    final localDb = LocalDbSource();
    final remote = _OfflineThenOnlineApi()..remoteProducts = [product];
    await localDb.saveProducts([product]);
    final posRepository = PosRepositoryImpl(
      localDbSource: localDb,
      remoteApiSource: remote,
    );

    final products = await posRepository.getProducts();

    expect(products.single.id, product.id);
    expect(posRepository.isUsingCachedProducts, isTrue);
  });

  test('offline checkout remains queued until pending orders sync', () async {
    final localDb = LocalDbSource();
    final remote = _OfflineThenOnlineApi()..remoteProducts = [product];
    final posRepository = PosRepositoryImpl(
      localDbSource: localDb,
      remoteApiSource: remote,
    );
    final order = OrderEntity(
      id: 'offline-order',
      items: [CartItemEntity(product: product)],
      subtotal: product.price,
      tax: 0,
      totalPrice: product.price,
      paidAmount: product.price,
      changeAmount: 0,
      paymentMethod: PosProvider.paymentCash,
      createdAt: DateTime(2026, 10, 3),
    );

    expect(await posRepository.saveOrder(order), isTrue);
    expect((await posRepository.getPendingOrders()).single.id, order.id);

    remote.isOnline = true;
    await posRepository.syncPendingOrders();

    expect(await posRepository.getPendingOrders(), isEmpty);
    expect(remote.syncAttempts, 2);
  });

  test('cart quantity cannot exceed available stock', () {
    expect(provider.addToCart(product), isTrue);
    expect(provider.addToCart(product), isTrue);
    expect(provider.addToCart(product), isFalse);
    expect(provider.getQuantity(product), 2);
    expect(provider.getRemainingStock(product), 0);
  });

  test('fixed discount, tax and cash change are calculated', () {
    provider.addToCart(product);
    provider.setDiscount(3000);
    provider.setTaxRate(0.11);
    provider.setServiceRate(0.05);
    provider.setCashReceived(50000);

    expect(provider.subtotal, 30000);
    expect(provider.discountAmount, 3000);
    expect(provider.tax, 2970);
    expect(provider.service, 1350);
    expect(provider.total, 31320);
    expect(provider.cashChange, 18680);
    expect(provider.canSubmitOrder, isTrue);
  });

  test('checkout saves payment details and deducts local product stock',
      () async {
    provider.addToCart(product);
    provider.setPaymentMethod(PosProvider.paymentQris);
    final totalBeforeCheckout = provider.total;

    final success = await provider.submitOrder(
        provider.checkoutPaidAmount, provider.paymentMethod);

    expect(success, isTrue);
    expect(repository.savedOrder?.paymentMethod, PosProvider.paymentQris);
    expect(repository.savedOrder?.paidAmount, totalBeforeCheckout);
    expect(repository.savedOrder?.items.single.quantity, 1);
    expect(provider.products.single.stock, 1);
    expect(provider.cart, isEmpty);
  });

  testWidgets('cashier can inspect and sync pending offline orders',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    repository.pendingOrders.add(
      OrderEntity(
        id: 'pending-1',
        items: [CartItemEntity(product: product)],
        subtotal: product.price,
        tax: 0,
        totalPrice: product.price,
        paidAmount: product.price,
        changeAmount: 0,
        paymentMethod: PosProvider.paymentCash,
        createdAt: DateTime(2026, 10, 3, 12),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: PosDashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1 transaksi tersimpan'), findsOneWidget);
    await tester.tap(find.text('Lihat antrean'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Test item × 1'), findsOneWidget);

    await tester.tap(find.text('Sinkronkan sekarang'));
    await tester.pumpAndSettle();

    expect(repository.syncCalls, 1);
    expect(find.text('Antrean transaksi sudah kosong.'), findsOneWidget);
  });

  testWidgets('payment details open only after Place order is pressed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: PosDashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tambah ke keranjang').first);
    await tester.pumpAndSettle();

    expect(find.text('Metode pembayaran'), findsNothing);
    expect(find.text('Uang diterima'), findsNothing);
    expect(find.text('Jenis'), findsNothing);
    expect(find.text('Layanan'), findsNothing);
    expect(find.text('PPN dari pengaturan admin'), findsOneWidget);

    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();

    expect(find.text('Metode pembayaran'), findsOneWidget);
    expect(find.text('Uang diterima'), findsOneWidget);
    expect(find.text('Kembalian'), findsOneWidget);
  });

  testWidgets('successful payment shows a transaction summary dialog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: PosDashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tambah ke keranjang').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QRIS').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi pembayaran').last);
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran berhasil'), findsOneWidget);
    expect(find.text('Metode pembayaran'), findsOneWidget);
    expect(find.text('Dibayar'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
  });
}
