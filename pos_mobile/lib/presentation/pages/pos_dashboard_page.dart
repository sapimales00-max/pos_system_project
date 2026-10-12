import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show Printing;
import 'package:provider/provider.dart';
import '../controllers/auth_provider.dart';
import '../controllers/pos_provider.dart';
import '../../domain/entities/product_entity.dart';
import 'admin_login_dialog.dart';
import 'admin_dashboard_page.dart';
import 'cashier_tools.dart';

const _ink = Color(0xFF1F1F1F);
const _muted = Color(0xFF8C7D73);
const _green = Color(0xFFC45A34);
const _canvas = Color(0xFFF6F3EE);

class PosDashboardPage extends StatefulWidget {
  const PosDashboardPage({super.key, this.showDemoProducts = true});

  final bool showDemoProducts;

  @override
  State<PosDashboardPage> createState() => _PosDashboardPageState();
}

class _PosDashboardPageState extends State<PosDashboardPage> {
  final _discountController = TextEditingController();
  final _cashReceivedController = TextEditingController();
  int _selectedSection = 0;
  bool _showSplashScreen = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() => _showSplashScreen = false);
      }
    });

    final provider = context.read<PosProvider>();
    final auth = context.read<AuthProvider?>();
    Future.microtask(() async {
      await auth?.initialize();
      await auth?.ensureCashierSession();
      try {
        await provider.refreshPendingOrders();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat antrean transaksi: $error')),
          );
        }
      }
      try {
        await provider.refreshSettings();
      } catch (_) {}

      try {
        await provider.refreshProducts();
      } catch (_) {}

      // Jika database belum memiliki produk (kosong), muat data demo bawaan
      if (provider.products.isEmpty) {
        provider.loadProducts([
          ProductEntity(
              id: '1',
              name: 'Kopi Susu Gula Aren',
              category: 'Kopi',
              price: 22000,
              stock: 99,
              imageUrl: ''),
          ProductEntity(
              id: '2',
              name: 'Americano',
              category: 'Kopi',
              price: 18000,
              stock: 99,
              imageUrl: ''),
          ProductEntity(
              id: '3',
              name: 'Caramel Latte',
              category: 'Kopi',
              price: 28000,
              stock: 99,
              imageUrl: ''),
          ProductEntity(
              id: '4',
              name: 'Es Teh Lemon',
              category: 'Teh',
              price: 12000,
              stock: 99,
              imageUrl: ''),
          ProductEntity(
              id: '5',
              name: 'Thai Tea',
              category: 'Teh',
              price: 18000,
              stock: 99,
              imageUrl: ''),
          ProductEntity(
              id: '6',
              name: 'Matcha Latte',
              category: 'Teh',
              price: 26000,
              stock: 99,
              imageUrl: ''),
          ProductEntity(
              id: '7',
              name: 'Lemon Squash',
              category: 'Segar',
              price: 20000,
              stock: 99,
              imageUrl: ''),
          ProductEntity(
              id: '8',
              name: 'Jus Alpukat',
              category: 'Segar',
              price: 24000,
              stock: 99,
              imageUrl: ''),
          ProductEntity(
              id: '9',
              name: 'Mango Smoothie',
              category: 'Segar',
              price: 25000,
              stock: 99,
              imageUrl: ''),
        ]);
      }

      if (auth?.isAdminLoggedIn == true && mounted) {
        setState(() => _selectedSection = 3);
      }
    });
  }

  @override
  void dispose() {
    _discountController.dispose();
    _cashReceivedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final auth = context.watch<AuthProvider>();

    if (_showSplashScreen) {
      return _buildSplashScreen(provider);
    }

    if (_selectedSection == 3 && !auth.isAdminLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedSection == 3 && !auth.isAdminLoggedIn) {
          setState(() => _selectedSection = 0);
        }
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1050;
        return Scaffold(
          backgroundColor: provider.bgAccentColor,
          appBar: isWide
              ? null
              : AppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  title: Text(
                    const [
                      'Menu.',
                      'Stok bahan',
                      'Histori',
                      'Admin Workspace.'
                    ][_selectedSection],
                    style: TextStyle(
                      fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F1F1F),
                    ),
                  ),
                  leading: _selectedSection == 0
                      ? null
                      : IconButton(
                          tooltip: 'Kembali ke order',
                          onPressed: () => setState(() => _selectedSection = 0),
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF1F1F1F)),
                        ),
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (isWide) _buildSidebar(provider),
                Expanded(
                  child: switch (_selectedSection) {
                    1 => const CashierIngredientsPage(),
                    2 => const CashierTransactionsPage(),
                    3 => const AdminDashboardPage(showSidebar: false),
                    _ => _buildCatalog(provider, isWide),
                  },
                ),
                if (isWide && _selectedSection == 0) _buildCartPanel(provider),
              ],
            ),
          ),
          bottomNavigationBar: isWide || _selectedSection != 0
              ? null
              : _buildMobileCartBar(context, provider),
        );
      },
    );
  }

  Widget _buildSidebar(PosProvider provider) {
    return Container(
      width: 76,
      margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Top Order Pill Button
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFF1F1F1F),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Image.asset(
                'web/favicon.png',
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.local_cafe_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Sidebar Navigation Buttons
          _buildSidebarNavButton(
            icon: Icons.desktop_windows_outlined,
            label: 'Menu',
            index: 0,
          ),
          const SizedBox(height: 16),
          _buildSidebarNavButton(
            icon: Icons.view_in_ar_rounded,
            label: 'Stok bahan',
            index: 1,
          ),
          const SizedBox(height: 16),
          _buildSidebarNavButton(
            icon: Icons.access_time_rounded,
            label: 'Histori',
            index: 2,
          ),
          const SizedBox(height: 16),
          _buildSidebarNavButton(
            icon: Icons.verified_user_outlined,
            label: 'Admin',
            index: 3,
            onTap: () async {
              final auth = context.read<AuthProvider>();
              if (!auth.isAdminLoggedIn) {
                await showAdminLoginDialog(context);
              }
              if (mounted && auth.isAdminLoggedIn) {
                setState(() => _selectedSection = 3);
              }
            },
          ),

          const Spacer(),

          // Bottom Cashier Profile Avatar
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F2EB),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                alignment: Alignment.center,
                child: Text(
                  'K1',
                  style: TextStyle(
                    fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: const Color(0xFF1F1F1F),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Kasir 1',
                style: TextStyle(
                  fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF8C7D73),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarNavButton({
    required IconData icon,
    required String label,
    required int index,
    VoidCallback? onTap,
  }) {
    final isActive = _selectedSection == index && onTap == null;
    return InkWell(
      onTap: onTap ?? () {
        setState(() => _selectedSection = index);
        if (index == 0) {
          context.read<PosProvider>().refreshProducts();
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF1F1F1F) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isActive ? Colors.white : const Color(0xFF8C7D73),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
              fontSize: 9,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              color: isActive ? const Color(0xFF1F1F1F) : const Color(0xFF8C7D73),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalog(PosProvider provider, bool isWide) {
    final categoriesList = ['Semua', ...provider.products.map((p) => p.category).toSet()];

    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 20, isWide ? 24 : 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Menu.',
                      style: TextStyle(
                        fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1F1F1F),
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_getFormattedHeaderDate()} · Pilih minuman, ketuk untuk menambah',
                      style: TextStyle(
                        fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8C7D73),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Search Bar Field
              SizedBox(
                width: 220,
                height: 42,
                child: TextField(
                  onChanged: provider.setSearchQuery,
                  style: TextStyle(
                    fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1F1F1F),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Cari minuman',
                    hintStyle: TextStyle(
                      fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                      color: const Color(0xFF8C7D73),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF8C7D73), size: 18),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Category Pills Filter
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: categoriesList.length,
              itemBuilder: (context, index) {
                final cat = categoriesList[index];
                final isSelected = (provider.selectedCategory == 'All' && cat == 'Semua') ||
                    provider.selectedCategory == cat;

                final count = cat == 'Semua' || cat == 'All'
                    ? provider.products.length
                    : provider.products.where((p) => p.category == cat).length;

                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: InkWell(
                    onTap: () => provider.setCategory(cat == 'Semua' ? 'All' : cat),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF1F1F1F) : const Color(0xFFF5F2EB),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF1F1F1F) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            cat,
                            style: TextStyle(
                              fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : const Color(0xFF3B2820),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$count',
                            style: TextStyle(
                              fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white70 : const Color(0xFF8C7D73),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),

          // Product Grid
          Expanded(
            child: LayoutBuilder(
              builder: (context, gridConstraints) {
                final width = gridConstraints.maxWidth;
                final columns = width < 480 ? 2 : 3;
                final products = provider.filteredProducts;

                if (products.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off_rounded, size: 42, color: Color(0xFF8C7D73)),
                        const SizedBox(height: 12),
                        Text(
                          'Minuman tidak ditemukan',
                          style: TextStyle(
                            fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF8C7D73),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: width < 600 ? 1.52 : 1.72,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) => _buildProductCard(provider, products[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(PosProvider provider, ProductEntity product) {
    final quantity = provider.getQuantity(product);
    final cardBgColor = _getCardBackgroundColor(product);
    final name = _capitalizeTitle(product.name);

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => provider.addToCart(product),
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Product Name (Top-Left) + Add Button / Quantity Badge (Top-Right)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1F1F1F),
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        if (quantity > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F1F1F),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'x$quantity',
                              style: TextStyle(
                                fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1F1F1F),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                        ),
                      ],
                    ),
                  ],
                ),

                const Spacer(),

                // Bottom Row: Price (Bottom-Left)
                Text(
                  _formatRupiah(product.price),
                  style: TextStyle(
                    fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1F1F1F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCartPanel(PosProvider provider) {
    return Container(
      width: 370,
      margin: const EdgeInsets.fromLTRB(0, 8, 12, 8),
      child: PhysicalShape(
        clipper: _ReceiptClipper(),
        color: Colors.white,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: _buildCartContents(provider, closeSheet: false),
        ),
      ),
    );
  }

  Widget _buildCartContents(PosProvider provider, {required bool closeSheet}) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF1F1F1F);
    const mutedGray = Color(0xFF8C7D73);

    final totalItems = provider.cart.fold(0, (sum, i) => sum + i.quantity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Store Name / Logo Header Above STRUK PESANAN
        Center(
          child: Column(
            children: [
              if (provider.storeLogo != null && provider.storeLogo!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    provider.storeLogo!,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                provider.storeName.isEmpty ? 'Lailain' : provider.storeName,
                style: TextStyle(
                  fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                  color: darkBrown,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            'STRUK PESANAN',
            style: TextStyle(
              fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
              color: mutedGray,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '${_getFormattedHeaderDate()} · [${provider.currentOrderCode}]',
            style: TextStyle(
              fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
              color: mutedGray,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _DashedDivider(),
        const SizedBox(height: 14),

        // Items List
        Expanded(
          child: provider.cart.isEmpty
              ? Center(
                  child: Text(
                    'Belum ada pesanan',
                    style: TextStyle(
                      fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                      color: mutedGray,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: provider.cart.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final item = provider.cart[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product.name,
                                style: TextStyle(
                                  fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                                  color: darkBrown,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatRupiah(item.totalPrice),
                                style: TextStyle(
                                  fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                                  color: mutedGray,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => provider.removeFromCart(item.product),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF1F1F1F), width: 1.5),
                                ),
                                child: const Icon(Icons.remove_rounded, size: 16, color: Color(0xFF1F1F1F)),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                '${item.quantity}',
                                style: TextStyle(
                                  fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                                  color: darkBrown,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => provider.addToCart(item.product),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF1F1F1F),
                                ),
                                child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
        ),

        const SizedBox(height: 10),
        const _DashedDivider(),
        const SizedBox(height: 12),

        // Subtotal, Diskon, Pajak PPN Breakdown
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Subtotal', style: TextStyle(fontFamily: GoogleFonts.bricolageGrotesque().fontFamily, color: mutedGray, fontSize: 12, fontWeight: FontWeight.w600)),
            Text(_formatRupiah(provider.subtotal), style: TextStyle(fontFamily: GoogleFonts.bricolageGrotesque().fontFamily, color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        if (provider.discountAmount > 0) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Diskon', style: TextStyle(fontFamily: GoogleFonts.bricolageGrotesque().fontFamily, color: mutedGray, fontSize: 12, fontWeight: FontWeight.w600)),
              Text('-${_formatRupiah(provider.discountAmount)}', style: TextStyle(fontFamily: GoogleFonts.bricolageGrotesque().fontFamily, color: terracotta, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Pajak PPN (${(provider.taxRate * 100).round()}%)', style: TextStyle(fontFamily: GoogleFonts.bricolageGrotesque().fontFamily, color: mutedGray, fontSize: 12, fontWeight: FontWeight.w600)),
            Text(_formatRupiah(provider.tax), style: TextStyle(fontFamily: GoogleFonts.bricolageGrotesque().fontFamily, color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        const _DashedDivider(),
        const SizedBox(height: 12),

        // Total Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'TOTAL · $totalItems ITEM',
              style: TextStyle(
                fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                color: mutedGray,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              _formatRupiah(provider.total),
              style: TextStyle(
                fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                color: terracotta,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Payment Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: provider.cart.isEmpty || provider.isLoading
                ? null
                : () => _showPaymentDialog(context, provider, closeSheet: closeSheet),
            style: FilledButton.styleFrom(
              backgroundColor: terracotta,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: provider.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    'Lanjut ke Pembayaran',
                    style: TextStyle(
                      fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),

        // Footer Barcode & Message
        const Center(child: _BarcodeWidget()),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Terima kasih, selamat menikmati.',
            style: TextStyle(
              fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
              color: mutedGray,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  void _showPaymentDialog(BuildContext context, PosProvider provider, {required bool closeSheet}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer<PosProvider>(
        builder: (context, currentProvider, child) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          title: Text(
            'Konfirmasi Pembayaran',
            style: TextStyle(
              fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1F1F1F),
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryRow('Total Tagihan', _formatRupiah(currentProvider.total), isTotal: true),
                  const SizedBox(height: 18),
                  _buildPaymentControls(currentProvider),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Kembali',
                style: TextStyle(
                  fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: currentProvider.isLoading || !currentProvider.canSubmitOrder
                  ? null
                  : () => _submitOrder(dialogContext, context, currentProvider, closeSheet: closeSheet),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC45A34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: currentProvider.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(
                currentProvider.isLoading ? 'Memproses...' : 'Konfirmasi Pembayaran',
                style: TextStyle(
                  fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentControls(PosProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Metode Pembayaran',
          style: TextStyle(
            fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
            color: const Color(0xFF1F1F1F),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildPaymentOption(provider, PosProvider.paymentCash, 'Tunai', Icons.payments_outlined),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPaymentOption(provider, PosProvider.paymentQris, 'QRIS', Icons.qr_code_2_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPaymentOption(provider, PosProvider.paymentTransfer, 'Transfer', Icons.account_balance_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (provider.paymentMethod == PosProvider.paymentCash) ...[
          TextField(
            controller: _cashReceivedController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
              fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
              fontWeight: FontWeight.w800,
            ),
            onChanged: (value) => provider.setCashReceived(double.tryParse(value.replaceAll('.', '')) ?? 0),
            decoration: InputDecoration(
              labelText: 'Uang Diterima',
              prefixText: 'Rp ',
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF6F3EE),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          _buildSummaryRow('Kembalian', _formatRupiah(provider.cashChange)),
          if (!provider.canSubmitOrder && provider.cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Uang diterima masih kurang dari total.',
                style: TextStyle(
                  fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                  color: const Color(0xFFB54236),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildPaymentOption(PosProvider provider, String method, String label, IconData icon) {
    final selected = provider.paymentMethod == method;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => provider.setPaymentMethod(method),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF5F2EB) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFFC45A34) : const Color(0xFFE2E8F0),
              width: selected ? 2.0 : 1.0,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: selected ? const Color(0xFFC45A34) : const Color(0xFF8C7D73)),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                  color: selected ? const Color(0xFFC45A34) : const Color(0xFF1F1F1F),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
            color: isTotal ? const Color(0xFF1F1F1F) : const Color(0xFF8C7D73),
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
            fontSize: isTotal ? 16 : 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
            color: isTotal ? const Color(0xFFC45A34) : const Color(0xFF1F1F1F),
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700,
            fontSize: isTotal ? 20 : 13,
          ),
        ),
      ],
    );
  }

  Widget _buildSplashScreen(PosProvider provider) {
    final font = GoogleFonts.bricolageGrotesque().fontFamily;
    final storeTitle = provider.storeName.trim().isEmpty ? 'Lailain' : provider.storeName.trim();

    return Scaffold(
      backgroundColor: provider.bgAccentColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo Container Badge
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset(
                  'web/favicon.png',
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => provider.storeLogo != null && provider.storeLogo!.isNotEmpty
                      ? Image.network(
                          provider.storeLogo!,
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.local_cafe_rounded,
                            size: 48,
                            color: Color(0xFFC45A34),
                          ),
                        )
                      : const Icon(
                          Icons.local_cafe_rounded,
                          size: 48,
                          color: Color(0xFFC45A34),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 22),

            // App / Store Name
            Text(
              '$storeTitle.',
              style: TextStyle(
                fontFamily: font,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1F1F1F),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),

            // Subtitle
            Text(
              'Point of Sale System & Smart Cashier',
              style: TextStyle(
                fontFamily: font,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8C7D73),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 32),

            // Loading Spinner
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC45A34)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCartBar(BuildContext context, PosProvider provider) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: () => _showMobileCart(context),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC45A34),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_outlined, size: 19),
                const SizedBox(width: 8),
                Text(
                  '${provider.cart.length}',
                  style: TextStyle(
                    fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lihat Pesanan',
                    style: TextStyle(
                      fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _formatRupiah(provider.total),
                  style: TextStyle(
                    fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMobileCart(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.85,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Consumer<PosProvider>(
            builder: (context, provider, child) =>
                _buildCartContents(provider, closeSheet: true),
          ),
        ),
      ),
    );
  }

  Future<void> _submitOrder(
    BuildContext dialogContext,
    BuildContext pageContext,
    PosProvider provider, {
    required bool closeSheet,
  }) async {
    final paidAmount = provider.checkoutPaidAmount;
    final changeAmount = provider.cashChange;
    final paymentMethodLabel = provider.paymentMethod == PosProvider.paymentCash
        ? 'Tunai'
        : provider.paymentMethod == PosProvider.paymentQris
            ? 'QRIS'
            : 'Transfer';

    final orderCode = provider.currentOrderCode;
    final cashierName =
        pageContext.read<AuthProvider?>()?.user?.name ??
            'Kasir 1';
    final cartItems = List<CartItemEntity>.from(provider.cart);
    final subtotal = provider.subtotal;
    final discountAmount = provider.discountAmount;
    final tax = provider.tax;
    final serviceAmount = provider.service;
    final total = provider.total;

    try {
      final success = await provider.submitOrder(paidAmount, provider.paymentMethod);
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      if (closeSheet && pageContext.mounted) {
        Navigator.of(pageContext).pop();
      }

      _discountController.clear();
      _cashReceivedController.clear();

      if (success && pageContext.mounted) {
        await _showCheckoutSuccessDialog(
          pageContext,
          orderCode: orderCode,
          total: total,
          paidAmount: paidAmount,
          changeAmount: changeAmount,
          paymentMethodLabel: paymentMethodLabel,
          isOffline: false,
          onPrintReceipt: () async {
            final pdfDoc = _buildThermalReceiptPdf(
              orderCode: orderCode,
              createdAt: DateTime.now(),
              cashierName: cashierName,
              items: cartItems,
              subtotal: subtotal,
              discountAmount: discountAmount,
              tax: tax,
              serviceAmount: serviceAmount,
              total: total,
              paidAmount: paidAmount,
              changeAmount: changeAmount,
              paymentMethod: paymentMethodLabel,
            );
            await Printing.layoutPdf(
              onLayout: (PdfPageFormat format) async => pdfDoc.save(),
              name: 'Struk_$orderCode',
            );
          },
        );
      }
    } catch (error) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('Proses transaksi gagal: $error'),
            backgroundColor: const Color(0xFFB54236),
          ),
        );
      }
    }
  }

  Future<void> _showCheckoutSuccessDialog(
    BuildContext context, {
    required String orderCode,
    required double total,
    required double paidAmount,
    required double changeAmount,
    required String paymentMethodLabel,
    required bool isOffline,
    required VoidCallback onPrintReceipt,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFE6F4EA),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF15803D), size: 24),
            ),
            const SizedBox(width: 10),
            Text(
              'Transaksi Berhasil',
              style: TextStyle(
                fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1F1F1F),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Struk: #$orderCode · $paymentMethodLabel',
                style: TextStyle(
                  fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                  color: const Color(0xFF8C7D73),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _buildSummaryRow('Total', _formatRupiah(total), isTotal: true),
              const SizedBox(height: 6),
              _buildSummaryRow('Dibayar', _formatRupiah(paidAmount)),
              const SizedBox(height: 6),
              _buildSummaryRow('Kembalian', _formatRupiah(changeAmount)),
              if (isOffline) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5E4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 16, color: Color(0xFF8B6526)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tersimpan secara lokal. Akan disinkronkan otomatis.',
                          style: TextStyle(color: Color(0xFF765A2C), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              onPrintReceipt();
            },
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.print_rounded, size: 18),
            label: Text(
              'Cetak Struk',
              style: TextStyle(
                fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC45A34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Selesai',
              style: TextStyle(
                fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Document _buildThermalReceiptPdf({
    required String orderCode,
    required DateTime createdAt,
    required String cashierName,
    required List<CartItemEntity> items,
    required double subtotal,
    required double discountAmount,
    required double tax,
    required double serviceAmount,
    required double total,
    required double paidAmount,
    required double changeAmount,
    required String paymentMethod,
  }) {
    final pdf = pw.Document();
    final paperFormat = PdfPageFormat(
      58 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 3 * PdfPageFormat.mm,
    );

    String moneyStr(double val) {
      final amt = val.round();
      final formatted = amt
          .toString()
          .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
      return 'Rp$formatted';
    }

    String timeStr(DateTime dt) {
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final y = dt.year;
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$d/$m/$y $h:$min';
    }

    pdf.addPage(
      pw.Page(
        pageFormat: paperFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                'KOPI KITA',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text('Jl. Raya Utama No. 12', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 4),
              pw.Text('- - - - - - - - - - - - - - - - - - - - - - - - - - - -', style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('No: #$orderCode', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text(timeStr(createdAt), style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Kasir: $cashierName', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Metode: $paymentMethod', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text('- - - - - - - - - - - - - - - - - - - - - - - - - - - -', style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 4),
              for (final item in items) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${item.product.name} x${item.quantity}',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        maxLines: 2,
                      ),
                    ),
                    pw.Text(
                      moneyStr(item.totalPrice),
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
              ],
              pw.SizedBox(height: 2),
              pw.Text('- - - - - - - - - - - - - - - - - - - - - - - - - - - -', style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(moneyStr(subtotal), style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              if (discountAmount > 0) ...[
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Diskon:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('-${moneyStr(discountAmount)}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ],
              if (tax > 0) ...[
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Pajak:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(moneyStr(tax), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ],
              pw.SizedBox(height: 4),
              pw.Text('- - - - - - - - - - - - - - - - - - - - - - - - - - - -', style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text(moneyStr(total), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Bayar:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(moneyStr(paidAmount), style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Kembali:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(moneyStr(changeAmount), style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Text('Terima Kasih Atas Kunjungan Anda!', style: const pw.TextStyle(fontSize: 7)),
            ],
          );
        },
      ),
    );
    return pdf;
  }

  String _getFormattedHeaderDate() {
    final now = DateTime.now();
    const days = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    final dayName = days[now.weekday % 7];
    final monthName = months[now.month - 1];
    final hour = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '$dayName, ${now.day} $monthName ${now.year} · $hour:$min';
  }

  bool _isCoffeeProduct(ProductEntity product) {
    final name = product.name.toLowerCase();
    final cat = product.category.toLowerCase();
    return name.contains('kopi') ||
        name.contains('coffee') ||
        name.contains('espresso') ||
        name.contains('americano') ||
        name.contains('latte') ||
        name.contains('cappuccino') ||
        name.contains('gula aren') ||
        name.contains('mocha') ||
        name.contains('caramel') ||
        cat.contains('kopi') ||
        (cat.contains('coffee') && !cat.contains('non'));
  }

  Color _getCardBackgroundColor(ProductEntity product) {
    if (_isCoffeeProduct(product)) {
      return const Color(0xFFF5A862); // Coklat / Warm Orange-Brown
    }
    return const Color(0xFFA2CE67); // Hijau / Non-Coffee Soft Green
  }

  Color _getDrinkLiquidColor(ProductEntity product) {
    final name = product.name.toLowerCase();
    if (_isCoffeeProduct(product)) {
      if (name.contains('americano') || name.contains('espresso') || name.contains('black')) {
        return const Color(0xFF2C1D11);
      }
      return const Color(0xFF5C3A21);
    }
    if (name.contains('matcha') || name.contains('alpukat') || name.contains('jus')) {
      return const Color(0xFF388E3C);
    }
    if (name.contains('teh') || name.contains('tea')) {
      return const Color(0xFFC05621);
    }
    return const Color(0xFFD4A31C);
  }

  String _getCategoryBadgeText(ProductEntity product) {
    if (_isCoffeeProduct(product)) {
      return 'COFFEE';
    }
    final cat = product.category.trim().toUpperCase();
    if (cat.isEmpty || cat == 'ALL' || cat == 'SEMUA') {
      return 'NON COFFEE';
    }
    return cat;
  }

  String _capitalizeTitle(String text) {
    if (text.trim().isEmpty) return text;
    return text.trim().split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _formatRupiah(num amount) {
    final value = amount.round().toString();
    final formatted =
        value.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => '.');
    return 'Rp$formatted';
  }
}

class _ReceiptClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    const toothWidth = 10.0;
    const toothHeight = 7.0;
    final count = (size.width / toothWidth).floor();

    path.moveTo(0, toothHeight);
    for (int i = 0; i < count; i++) {
      path.lineTo((i + 0.5) * toothWidth, 0);
      path.lineTo((i + 1) * toothWidth, toothHeight);
    }
    path.lineTo(size.width, toothHeight);
    path.lineTo(size.width, size.height - toothHeight);

    for (int i = count; i > 0; i--) {
      path.lineTo((i - 0.5) * toothWidth, size.height);
      path.lineTo((i - 1) * toothWidth, size.height - toothHeight);
    }
    path.lineTo(0, size.height - toothHeight);
    path.lineTo(0, toothHeight);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider({this.color = const Color(0xFFD6C8BC)});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth;
        const dashWidth = 5.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            );
          }),
        );
      },
    );
  }
}

class _BarcodeWidget extends StatelessWidget {
  const _BarcodeWidget();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _Bar(2.0), _Bar(1.0), _Bar(3.0), _Bar(1.0), _Bar(4.0), _Bar(2.0), _Bar(1.0),
          _Bar(3.0), _Bar(1.0), _Bar(2.0), _Bar(4.0), _Bar(1.0), _Bar(3.0), _Bar(2.0),
          _Bar(1.0), _Bar(4.0), _Bar(2.0), _Bar(1.0), _Bar(3.0), _Bar(1.0), _Bar(2.0),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.width);
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      color: const Color(0xFF1F1F1F),
    );
  }
}

class _CupPainter extends CustomPainter {
  final Color drinkColor;
  final Color outlineColor;

  _CupPainter({required this.drinkColor, this.outlineColor = const Color(0xFF1F1F1F)});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Straw ( angled black line/rect coming out top )
    final strawPaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.fill;
    final strawPath = Path()
      ..moveTo(w * 0.48, h * 0.0)
      ..lineTo(w * 0.58, h * 0.0)
      ..lineTo(w * 0.44, h * 0.28)
      ..lineTo(w * 0.34, h * 0.28)
      ..close();
    canvas.drawPath(strawPath, strawPaint);

    // Lid ( Dome / Rounded Trapezoid )
    final lidPaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.fill;
    final lidRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.22, w * 0.76, h * 0.10),
      const Radius.circular(6),
    );
    canvas.drawRRect(lidRect, lidPaint);

    // Cup Body ( Tapered Trapezoid )
    final cupPath = Path()
      ..moveTo(w * 0.18, h * 0.32)
      ..lineTo(w * 0.82, h * 0.32)
      ..lineTo(w * 0.72, h * 0.95)
      ..cubicTo(w * 0.70, h * 0.99, w * 0.30, h * 0.99, w * 0.28, h * 0.95)
      ..close();

    // Cup Shadow
    canvas.drawShadow(cupPath, Colors.black.withValues(alpha: 0.25), 5.0, true);

    // Fill Liquid
    final fillPaint = Paint()
      ..color = drinkColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(cupPath, fillPaint);

    // Cup Outline
    final strokePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(cupPath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _CupPainter oldDelegate) =>
      oldDelegate.drinkColor != drinkColor;
}
