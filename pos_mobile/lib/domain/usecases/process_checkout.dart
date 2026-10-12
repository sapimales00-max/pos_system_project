import '../entities/order_entity.dart';
import '../repositories/pos_repository.dart';

class ProcessCheckoutUseCase {
  final PosRepository repository;

  ProcessCheckoutUseCase(this.repository);

  Future<bool> execute(OrderEntity order) async {
    if (order.paidAmount < order.totalPrice) {
      throw Exception("Jumlah pembayaran kurang dari total tagihan!");
    }
    return await repository.saveOrder(order);
  }
}
