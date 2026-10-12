import '../../domain/entities/product_entity.dart';
import '../../domain/entities/order_entity.dart';

class LocalDbSource {
  final List<ProductEntity> _products = [];
  final List<OrderEntity> _orders = [];
  final List<OrderEntity> _pendingSyncOrders = [];

  Future<List<ProductEntity>> getProducts() async {
    return List.unmodifiable(_products);
  }

  Future<List<OrderEntity>> getOrders() async {
    return List.unmodifiable(_orders);
  }

  Future<List<OrderEntity>> getPendingOrders() async {
    return List.unmodifiable(_pendingSyncOrders);
  }

  Future<void> saveProducts(List<ProductEntity> products) async {
    _products
      ..clear()
      ..addAll(products);
  }

  Future<void> insertOrder(OrderEntity order) async {
    _orders.add(order);
    if (!_pendingSyncOrders.any((pending) => pending.id == order.id)) {
      _pendingSyncOrders.add(order);
    }
  }

  Future<void> markOrderSynced(OrderEntity order) async {
    _pendingSyncOrders.removeWhere((pending) => pending.id == order.id);
  }
}
