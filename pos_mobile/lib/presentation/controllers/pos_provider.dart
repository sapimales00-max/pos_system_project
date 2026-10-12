import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/usecases/process_checkout.dart';
import '../../data/datasources/remote_api_source.dart';

class PosProvider extends ChangeNotifier {
  static const paymentCash = 'CASH';
  static const paymentQris = 'QRIS';
  static const paymentTransfer = 'BANK_TRANSFER';

  final ProcessCheckoutUseCase processCheckoutUseCase;

  PosProvider({
    required this.processCheckoutUseCase,
    this.remoteApiSource,
  });

  List<ProductEntity> _products = [];
  List<OrderEntity> _pendingOrders = [];
  final RemoteApiSource? remoteApiSource;
  final List<CartItemEntity> _cart = [];
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _productLoadError;
  double _discountValue = 0;
  double _taxRate = 0.10;
  double _serviceRate = 0;
  String _paymentMethod = paymentCash;
  double _cashReceived = 0;
  int _orderSequence = 1;
  Color _bgAccentColor = const Color(0xFFF6F3EE);
  String _storeName = 'Lailain';
  String? _storeLogo;

  List<ProductEntity> get products => _products;
  List<OrderEntity> get pendingOrders => List.unmodifiable(_pendingOrders);
  List<CartItemEntity> get cart => List.unmodifiable(_cart);
  String get selectedCategory => _selectedCategory;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get productLoadError => _productLoadError;
  Color get bgAccentColor => _bgAccentColor;
  String get storeName => _storeName;
  String? get storeLogo => _storeLogo;

  void setStoreProfile({required String name, String? logo}) {
    _storeName = name.trim().isEmpty ? 'Lailain' : name.trim();
    if (logo != null) _storeLogo = logo;
    notifyListeners();
  }
  bool get isUsingCachedProducts =>
      processCheckoutUseCase.repository.isUsingCachedProducts;
  double get discountValue => _discountValue;
  double get taxRate => _taxRate;
  double get serviceRate => _serviceRate;
  String get paymentMethod => _paymentMethod;
  double get cashReceived => _cashReceived;
  int get orderSequence => _orderSequence;
  String get currentOrderCode => 'A-${_orderSequence.toString().padLeft(5, '0')}';
  double get cashChange => math.max(0, _cashReceived - total).toDouble();
  double get checkoutPaidAmount =>
      _paymentMethod == paymentCash ? _cashReceived : total;
  bool get canSubmitOrder =>
      _cart.isNotEmpty &&
      (_paymentMethod != paymentCash || _cashReceived >= total);

  double get subtotal => _cart.fold(0, (sum, item) => sum + item.totalPrice);
  double get discountAmount =>
      math.min(subtotal, _discountValue).roundToDouble();

  double get taxableSubtotal => subtotal - discountAmount;
  double get tax => (taxableSubtotal * _taxRate).roundToDouble();
  double get service => (taxableSubtotal * _serviceRate).roundToDouble();
  double get total => taxableSubtotal + tax + service;

  void setDiscount(double value) {
    _discountValue = value.clamp(0, double.infinity);
    notifyListeners();
  }

  void setTaxRate(double rate) {
    _taxRate = rate.clamp(0, 1);
    notifyListeners();
  }

  void setServiceRate(double rate) {
    _serviceRate = rate.clamp(0, 1);
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    if (![paymentCash, paymentQris, paymentTransfer].contains(method)) return;
    _paymentMethod = method;
    notifyListeners();
  }

  void setCashReceived(double amount) {
    _cashReceived = math.max(0, amount).toDouble();
    notifyListeners();
  }

  // Inisialisasi Data Dummy / Real dari Repository
  void loadProducts(List<ProductEntity> fetchedProducts) {
    _products = fetchedProducts;
    notifyListeners();
  }

  void setBgAccentColor(Color color) {
    _bgAccentColor = color;
    notifyListeners();
  }

  Future<void> refreshProducts() async {
    _isLoading = true;
    _productLoadError = null;
    notifyListeners();
    try {
      _products = await processCheckoutUseCase.repository.getProducts();
      await refreshPendingOrders();
    } catch (error) {
      _productLoadError = error.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshPendingOrders() async {
    _pendingOrders = await processCheckoutUseCase.repository.getPendingOrders();
    final api = remoteApiSource;
    if (api != null) {
      try {
        final res = await http.get(
          Uri.parse('${RemoteApiSource.baseUrl}/transactions'),
          headers: api.headers,
        );
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final list = (body['data'] as List<dynamic>? ?? []);
          int maxSeq = 1;
          for (final item in list) {
            final raw = (item['order_number'] ?? item['orderNumber'] ?? '').toString().trim();
            final match = RegExp(r'^A-(\d{1,5})$', caseSensitive: false).firstMatch(raw);
            if (match != null) {
              final parsed = int.tryParse(match.group(1)!);
              if (parsed != null && parsed < 100000 && parsed >= maxSeq) {
                maxSeq = parsed + 1;
              }
            }
          }
          _orderSequence = maxSeq;
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> syncPendingOrders() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();
    try {
      await processCheckoutUseCase.repository.syncPendingOrders();
      await refreshPendingOrders();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> refreshSettings() async {
    final api = remoteApiSource;
    if (api == null) return;
    final settings = await api.getPublicSettings();
    final paymentSettings =
        settings['tax_and_service'] as Map<String, dynamic>?;
    if (paymentSettings == null) return;
    final taxPercent = double.tryParse('${paymentSettings['taxRate']}');
    final servicePercent = double.tryParse('${paymentSettings['serviceRate']}');
    if (taxPercent != null) _taxRate = (taxPercent / 100).clamp(0, 1);
    if (servicePercent != null) {
      _serviceRate = (servicePercent / 100).clamp(0, 1);
    }
    notifyListeners();
  }

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // Filter Produk Berdasarkan Kategori & Pencarian
  List<ProductEntity> get filteredProducts {
    return _products.where((p) {
      final matchesCategory =
          _selectedCategory == 'All' || p.category == _selectedCategory;
      final matchesSearch =
          p.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  // Operasi Keranjang (Cart)
  bool addToCart(ProductEntity product) {
    final index = _cart.indexWhere((item) => item.product.id == product.id);
    final availableStock = product.stock <= 0 ? 999 : product.stock;
    if (index >= 0) {
      if (_cart[index].quantity >= availableStock) return false;
      _cart[index].quantity++;
    } else {
      _cart.add(CartItemEntity(product: product, quantity: 1));
    }
    notifyListeners();
    return true;
  }

  void removeFromCart(ProductEntity product) {
    final index = _cart.indexWhere((item) => item.product.id == product.id);
    if (index >= 0) {
      if (_cart[index].quantity > 1) {
        _cart[index].quantity--;
      } else {
        _cart.removeAt(index);
      }
      notifyListeners();
    }
  }

  int getQuantity(ProductEntity product) {
    final index = _cart.indexWhere((item) => item.product.id == product.id);
    return index >= 0 ? _cart[index].quantity : 0;
  }

  int getRemainingStock(ProductEntity product) =>
      math.max(0, product.stock - getQuantity(product));

  // Proses Selesai Bayar
  Future<bool> submitOrder(double paidAmount, String paymentMethod) async {
    _isLoading = true;
    notifyListeners();

    try {
      final orderCode = 'A-${_orderSequence.toString().padLeft(4, '0')}';
      final newOrder = OrderEntity(
        id: const Uuid().v4(),
        orderNumber: orderCode,
        items: List.from(_cart),
        subtotal: subtotal,
        discountAmount: discountAmount,
        tax: tax,
        taxRate: _taxRate,
        serviceAmount: service,
        serviceRate: _serviceRate,
        totalPrice: total,
        paidAmount: paidAmount,
        changeAmount: paidAmount - total,
        paymentMethod: paymentMethod,
        createdAt: DateTime.now(),
      );

      final success = await processCheckoutUseCase.execute(newOrder);
      if (success) {
        _orderSequence++;
        await refreshPendingOrders();
        final quantities = {
          for (final item in _cart) item.product.id: item.quantity,
        };
        _products = _products
            .map((product) => ProductEntity(
                  id: product.id,
                  name: product.name,
                  category: product.category,
                  price: product.price,
                  stock: math.max(
                      0, product.stock - (quantities[product.id] ?? 0)),
                  imageUrl: product.imageUrl,
                ))
            .toList();
        _cart.clear();
        _cashReceived = 0;
        _discountValue = 0;
      }
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }
}
