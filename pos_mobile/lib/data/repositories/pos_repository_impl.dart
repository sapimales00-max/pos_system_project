import '../../domain/entities/product_entity.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/repositories/pos_repository.dart';
import '../datasources/local_db_source.dart';
import '../datasources/remote_api_source.dart';

class PosRepositoryImpl implements PosRepository {
  final LocalDbSource localDbSource;
  final RemoteApiSource remoteApiSource;
  bool _isUsingCachedProducts = false;

  @override
  bool get isUsingCachedProducts => _isUsingCachedProducts;

  PosRepositoryImpl({
    required this.localDbSource,
    required this.remoteApiSource,
  });

  @override
  Future<List<ProductEntity>> getProducts() async {
    _isUsingCachedProducts = false;
    final pendingOrders = await localDbSource.getPendingOrders();
    if (pendingOrders.isNotEmpty) {
      await syncPendingOrders();
    }

    final cachedProducts = await localDbSource.getProducts();
    try {
      final remoteProducts = await remoteApiSource.getProducts();
      if (remoteProducts.isNotEmpty || cachedProducts.isEmpty) {
        await localDbSource.saveProducts(remoteProducts);
        return remoteProducts;
      }
      _isUsingCachedProducts = true;
      return cachedProducts;
    } on Exception {
      if (cachedProducts.isNotEmpty) {
        _isUsingCachedProducts = true;
        return cachedProducts;
      }
      rethrow;
    }
  }

  @override
  Future<List<OrderEntity>> getPendingOrders() async {
    return localDbSource.getPendingOrders();
  }

  @override
  Future<bool> saveOrder(OrderEntity order) async {
    await localDbSource.insertOrder(order);

    try {
      await remoteApiSource.syncOrder(order);
      await localDbSource.markOrderSynced(order);
    } on Exception {
      // Keep the locally saved order queued for the next sync attempt.
    }
    return true;
  }

  @override
  Future<void> syncPendingOrders() async {
    final pendingOrders = await localDbSource.getPendingOrders();
    for (final order in pendingOrders) {
      var attempts = 0;
      var synced = false;
      while (attempts < 2 && !synced) {
        try {
          await remoteApiSource.syncOrder(order);
          await localDbSource.markOrderSynced(order);
          synced = true;
        } on Exception {
          attempts++;
        }
      }
    }
  }
}
