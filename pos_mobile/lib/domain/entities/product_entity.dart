class ProductEntity {
  final String id;
  final String name;
  final String category;
  final double price;
  final int stock;
  final String imageUrl;

  ProductEntity({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    required this.imageUrl,
  });
}

class CartItemEntity {
  final ProductEntity product;
  int quantity;

  CartItemEntity({
    required this.product,
    this.quantity = 1,
  });

  double get totalPrice => product.price * quantity;
}
