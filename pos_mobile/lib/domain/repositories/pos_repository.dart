import '../entities/product_entity.dart';
import '../entities/order_entity.dart';

abstract class PosRepository {
  bool get isUsingCachedProducts;
  Future<List<ProductEntity>> getProducts();
  Future<List<OrderEntity>> getPendingOrders();
  Future<bool> saveOrder(OrderEntity order);
  Future<void> syncPendingOrders();
}
