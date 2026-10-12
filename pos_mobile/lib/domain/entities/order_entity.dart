import 'product_entity.dart';

class OrderEntity {
  final String id;
  final String? orderNumber;
  final List<CartItemEntity> items;
  final double subtotal;
  final double discountAmount;
  final double tax;
  final double taxRate;
  final double serviceAmount;
  final double serviceRate;
  final double totalPrice;
  final double paidAmount;
  final double changeAmount;
  final String paymentMethod;
  final DateTime createdAt;

  OrderEntity({
    required this.id,
    this.orderNumber,
    required this.items,
    required this.subtotal,
    this.discountAmount = 0,
    required this.tax,
    this.taxRate = 0.10,
    this.serviceAmount = 0,
    this.serviceRate = 0,
    required this.totalPrice,
    required this.paidAmount,
    required this.changeAmount,
    required this.paymentMethod,
    required this.createdAt,
  });
}
