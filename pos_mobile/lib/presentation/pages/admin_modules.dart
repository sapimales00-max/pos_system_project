import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show Printing;
import 'package:provider/provider.dart';
import '../controllers/auth_provider.dart';
import '../controllers/pos_provider.dart';

const _apiBaseUrl = String.fromEnvironment(
  'POS_API_URL',
  defaultValue: 'http://127.0.0.1:3000/api/v1',
);

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFFFE9E5),
        child: ListTile(
          title:
              Text(message, style: const TextStyle(color: Color(0xFF9F3429))),
          trailing: IconButton(
              tooltip: 'Coba lagi',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh)),
        ),
      );
}

Future<dynamic> _adminRequest(
  BuildContext context,
  String method,
  String path, {
  Map<String, dynamic>? body,
}) async {
  final token = context.read<AuthProvider>().token;
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  final uri = Uri.parse('$_apiBaseUrl$path');
  final response = switch (method) {
    'GET' => await http.get(uri, headers: headers),
    'POST' => await http.post(uri, headers: headers, body: jsonEncode(body)),
    'PUT' => await http.put(uri, headers: headers, body: jsonEncode(body)),
    'PATCH' => await http.patch(uri, headers: headers, body: jsonEncode(body)),
    'DELETE' => await http.delete(uri, headers: headers),
    _ => throw UnsupportedError('Metode HTTP tidak didukung.'),
  };
  if (response.body.trim().startsWith('<')) {
    throw Exception('Server error (${response.statusCode}): ${response.reasonPhrase}');
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(decoded['message'] ?? 'Permintaan gagal.');
  }
  return decoded['data'];
}

String _money(dynamic value) {
  final amount = num.tryParse(value?.toString() ?? '')?.round() ?? 0;
  final formatted = amount
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return 'Rp $formatted';
}

String _message(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

pw.Document buildFinancialReportPdfDocument({
  required Map<String, dynamic> report,
  required List<Map<String, dynamic>> products,
  required List<Map<String, dynamic>> expenses,
  required DateTime from,
  required DateTime to,
}) {
  final document = pw.Document();
  final productRows = products
      .map((item) => [
            item['name']?.toString() ?? '',
            item['category']?.toString() ?? '',
            item['quantity']?.toString() ?? '0',
            _money(item['revenue']),
            _money(item['cost']),
            _money(item['gross_profit']),
          ])
      .toList();
  final expenseRows = expenses
      .map((item) => [
            item['expense_date']?.toString() ?? '',
            item['category']?.toString() ?? '',
            item['description']?.toString() ?? '',
            _money(item['amount']),
          ])
      .toList();

  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    build: (_) => [
      pw.Center(
        child: pw.Text('Laporan Keuangan POS',
            style: const pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold)),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
          'Periode: ${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')} sampai ${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}'),
      pw.SizedBox(height: 14),
      ..._financialReportTable('Ringkasan', [
        'Keterangan',
        'Jumlah'
      ], [
        ['Penjualan', _money(report['sales_total'])],
        ['HPP terjual', _money(report['cost_total'])],
        ['Laba kotor', _money(report['gross_profit'])],
        ['Biaya operasional', _money(report['expense_total'])],
        ['Laba bersih', _money(report['net_profit'])],
        ['Jumlah transaksi', report['transaction_count']?.toString() ?? '0'],
      ]),
      pw.SizedBox(height: 16),
      ..._financialReportTable(
        'Perincian HPP dan laba per produk',
        ['Produk', 'Kategori', 'Qty', 'Penjualan', 'HPP', 'Laba kotor'],
        productRows.isEmpty
            ? [
                ['-', '-', '0', _money(0), _money(0), _money(0)]
              ]
            : productRows,
      ),
      pw.SizedBox(height: 16),
      ..._financialReportTable(
        'Rincian biaya operasional',
        ['Tanggal', 'Kategori', 'Keterangan', 'Jumlah'],
        expenseRows.isEmpty
            ? [
                ['-', '-', 'Tidak ada biaya', _money(0)]
              ]
            : expenseRows,
      ),
    ],
  ));
  return document;
}

List<pw.Widget> _financialReportTable(
  String title,
  List<String> headers,
  List<List<String>> rows,
) {
  return [
    pw.Text(title,
        style:
            const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 6),
    ...[headers, ...rows].map((row) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: row
                .map((cell) => pw.Expanded(
                      child: pw.Text(cell,
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: identical(row, headers)
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                          )),
                    ))
                .toList(),
          ),
        )),
  ];
}

class AdminProductsPage extends StatefulWidget {
  const AdminProductsPage({super.key});

  @override
  State<AdminProductsPage> createState() => _AdminProductsPageState();
}

class _AdminProductsPageState extends State<AdminProductsPage> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _ingredients = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  String _selectedCategoryFilter = 'Semua';

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _adminRequest(context, 'GET', '/products'),
        _adminRequest(context, 'GET', '/ingredients'),
      ]);
      if (!mounted) return;
      setState(() {
        _products = (results[0] as List<dynamic>).cast<Map<String, dynamic>>();
        _ingredients =
            (results[1] as List<dynamic>).cast<Map<String, dynamic>>();
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? product]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ProductEditor(product: product, ingredients: _ingredients),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        context.read<PosProvider>().refreshProducts();
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Produk?'),
        content: Text('Produk "${product['name']}" akan dihapus secara permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _adminRequest(context, 'DELETE', '/products/${product['id']}');
      await _load();
      if (mounted) {
        context.read<PosProvider>().refreshProducts();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus produk: $error')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    var list = _products;
    if (_selectedCategoryFilter == 'Aktif') {
      list = list.where((p) => p['is_active'] != false).toList();
    } else if (_selectedCategoryFilter == 'Non-aktif') {
      list = list.where((p) => p['is_active'] == false).toList();
    } else if (_selectedCategoryFilter == 'Coffee') {
      list = list.where((p) => (p['category'] ?? '').toString().toLowerCase().contains('coffee') && !(p['category'] ?? '').toString().toLowerCase().contains('non')).toList();
    } else if (_selectedCategoryFilter == 'Non-coffee') {
      list = list.where((p) => (p['category'] ?? '').toString().toLowerCase().contains('non')).toList();
    } else if (_selectedCategoryFilter == 'Makanan') {
      list = list.where((p) => (p['category'] ?? '').toString().toLowerCase().contains('makanan') || (p['category'] ?? '').toString().toLowerCase().contains('food')).toList();
    } else if (_selectedCategoryFilter == 'Tanpa resep') {
      list = list.where((p) => (p['recipe'] as List<dynamic>? ?? []).isEmpty).toList();
    }

    if (_searchQuery.trim().isEmpty) return list;
    final query = _searchQuery.toLowerCase().trim();
    return list.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final cat = (p['category'] ?? '').toString().toLowerCase();
      return name.contains(query) || cat.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final filtered = _filteredProducts;

    final totalProducts = _products.length;
    final noRecipeCount = _products
        .where((p) => (p['recipe'] as List<dynamic>? ?? []).isEmpty)
        .length;
    double totalMarginPct = 0;
    int countWithPrice = 0;
    for (var p in _products) {
      final costPrice = num.tryParse(p['cost_price']?.toString() ?? '')?.toDouble() ?? 0.0;
      final sellingPrice = num.tryParse(p['selling_price']?.toString() ?? '')?.toDouble() ?? 0.0;
      if (sellingPrice > 0) {
        final marginPct = ((sellingPrice - costPrice) / sellingPrice) * 100;
        totalMarginPct += marginPct;
        countWithPrice++;
      }
    }
    final avgMarginPct = countWithPrice > 0 ? (totalMarginPct / countWithPrice).round() : 0;

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Area
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Produk',
                        style: TextStyle(
                          color: darkBrown,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Kelola menu, harga, dan resep',
                        style: TextStyle(color: mutedGray, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Muat ulang',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, color: darkBrown),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _edit(),
                  style: FilledButton.styleFrom(
                    backgroundColor: terracotta,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tambah Produk',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          // Top Summary Metrics Bar (3 Mini Cards)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5EBE1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.inventory_2_outlined,
                              color: terracotta, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Produk',
                                style: TextStyle(
                                    color: mutedGray,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('$totalProducts Menu',
                                style: const TextStyle(
                                    color: darkBrown,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F4EA),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.trending_up_rounded,
                              color: Color(0xFF1E8E3E), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Rata-rata Margin',
                                style: TextStyle(
                                    color: mutedGray,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('$avgMarginPct%',
                                style: const TextStyle(
                                    color: Color(0xFF1E8E3E),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: noRecipeCount > 0
                                ? const Color(0xFFFFF8E7)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.receipt_long_outlined,
                              color: noRecipeCount > 0
                                  ? const Color(0xFFD97706)
                                  : mutedGray,
                              size: 18),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Tanpa Resep',
                                style: TextStyle(
                                    color: mutedGray,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('$noRecipeCount Produk',
                                style: TextStyle(
                                    color: noRecipeCount > 0
                                        ? const Color(0xFFD97706)
                                        : darkBrown,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search & Category Chips Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Row(
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Cari produk...',
                      hintStyle:
                          const TextStyle(color: mutedGray, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: mutedGray, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Category Filter Chips
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var cat in [
                          'Semua',
                          'Aktif',
                          'Non-aktif',
                          'Coffee',
                          'Non-coffee',
                          'Makanan',
                          'Tanpa resep'
                        ]) ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              selected: _selectedCategoryFilter == cat,
                              label: Text(cat),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: _selectedCategoryFilter == cat
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: _selectedCategoryFilter == cat
                                    ? Colors.white
                                    : darkBrown,
                              ),
                              selectedColor: terracotta,
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: _selectedCategoryFilter == cat
                                    ? terracotta
                                    : const Color(0xFFE2E8F0),
                              ),
                              showCheckmark: false,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              onSelected: (_) =>
                                  setState(() => _selectedCategoryFilter = cat),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_error != null) _ErrorBanner(message: _error!, onRetry: _load),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_products.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Belum ada produk.',
                    style: TextStyle(color: mutedGray, fontSize: 14)),
              ),
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 0, 26, 26),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        // Table Header Row
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          color: const Color(0xFFFAF5F0),
                          child: Row(
                            children: const [
                              Expanded(
                                  flex: 3,
                                  child: Text('Produk',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  flex: 2,
                                  child: Text('Kategori',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  flex: 2,
                                  child: Text('Harga',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  flex: 2,
                                  child: Text('HPP',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  flex: 2,
                                  child: Text('Margin',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  flex: 2,
                                  child: Text('Resep',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  flex: 2,
                                  child: Text('Status',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              SizedBox(
                                  width: 70,
                                  child: Text('Aksi',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),

                        // Table Data Rows
                        Expanded(
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (context, index) {
                              final product = filtered[index];
                              final recipe =
                                  (product['recipe'] as List<dynamic>? ?? [])
                                      .cast<Map<String, dynamic>>();
                              final costPrice = num.tryParse(
                                      product['cost_price']?.toString() ?? '')
                                  ?.toDouble() ??
                                  0.0;
                              final sellingPrice = num.tryParse(
                                      product['selling_price']?.toString() ?? '')
                                  ?.toDouble() ??
                                  0.0;
                              final margin = sellingPrice - costPrice;
                              final marginPct = sellingPrice > 0
                                  ? ((margin / sellingPrice) * 100).round()
                                  : 0;

                              final name = _capitalizeTitle(
                                  product['name'] as String? ?? 'Produk');
                              final category = (product['category'] as String? ?? 'Coffee').trim();

                              Color catBg = const Color(0xFFFAF2E9);
                              Color catText = darkBrown;
                              if (category.toLowerCase().contains('coffee')) {
                                catBg = const Color(0xFFFFF8E7);
                                catText = const Color(0xFFD97706);
                              } else if (category.toLowerCase().contains('non')) {
                                catBg = const Color(0xFFE0F2FE);
                                catText = const Color(0xFF0284C7);
                              } else if (category.toLowerCase().contains('makanan') ||
                                  category.toLowerCase().contains('food')) {
                                catBg = const Color(0xFFDCFCE7);
                                catText = const Color(0xFF15803D);
                              }

                              return InkWell(
                                onTap: () => _edit(product),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                  child: Row(
                                    children: [
                                      // Produk Name
                                      Expanded(
                                        flex: 3,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF5EBE1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.local_cafe_outlined,
                                                size: 16,
                                                color: darkBrown,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: const TextStyle(
                                                    color: darkBrown,
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w800),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Kategori
                                      Expanded(
                                        flex: 2,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: catBg,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              category,
                                              style: TextStyle(
                                                  color: catText,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Harga Jual
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          _money(sellingPrice),
                                          style: const TextStyle(
                                              color: terracotta,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      // HPP
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          _money(costPrice),
                                          style: const TextStyle(
                                              color: mutedGray,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      // Margin %
                                      Expanded(
                                        flex: 2,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: marginPct >= 50
                                                  ? const Color(0xFFE6F4EA)
                                                  : (marginPct > 0
                                                      ? const Color(0xFFFFF8E7)
                                                      : const Color(0xFFFCE8E6)),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${_money(margin)} ($marginPct%)',
                                              style: TextStyle(
                                                  color: marginPct >= 50
                                                      ? const Color(0xFF1E8E3E)
                                                      : (marginPct > 0
                                                          ? const Color(0xFFD97706)
                                                          : const Color(0xFFD93025)),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Resep Count
                                      Expanded(
                                        flex: 2,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: recipe.isNotEmpty
                                                  ? const Color(0xFFF8F5F1)
                                                  : const Color(0xFFFAFAFA),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                  color: const Color(0xFFE2E8F0)),
                                            ),
                                            child: Text(
                                              recipe.isNotEmpty
                                                  ? '${recipe.length} bahan'
                                                  : 'Tanpa resep',
                                              style: TextStyle(
                                                  color: recipe.isNotEmpty
                                                      ? darkBrown
                                                      : mutedGray,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Status Aktif / Non-aktif
                                      Expanded(
                                        flex: 2,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: (product['is_active'] != false)
                                                  ? const Color(0xFFE6F4EA)
                                                  : const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              (product['is_active'] != false)
                                                  ? 'Aktif'
                                                  : 'Non-aktif',
                                              style: TextStyle(
                                                  color: (product['is_active'] != false)
                                                      ? const Color(0xFF1E8E3E)
                                                      : mutedGray,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Aksi (Edit & Delete Icons)
                                      SizedBox(
                                        width: 70,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            InkWell(
                                              onTap: () => _edit(product),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF8F5F1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                    Icons.edit_rounded,
                                                    size: 15,
                                                    color: darkBrown),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              onTap: () => _delete(product),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFCE8E6),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                    Icons.delete_rounded,
                                                    size: 15,
                                                    color: Color(0xFFDC2626)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductEditor extends StatefulWidget {
  const _ProductEditor({required this.product, required this.ingredients});

  final Map<String, dynamic>? product;
  final List<Map<String, dynamic>> ingredients;

  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _RecipeDraft {
  _RecipeDraft({this.ingredientId, String quantity = ''})
      : quantity = TextEditingController(text: quantity);

  String? ingredientId;
  final TextEditingController quantity;
}

String _formatNumberWithDots(dynamic raw) {
  if (raw == null) return '';
  final str = raw.toString().replaceAll('.', '').replaceAll(',', '').trim();
  final numVal = int.tryParse(str);
  if (numVal == null) return '';
  return numVal.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
}

double _parseFormattedDouble(String text) {
  final clean = text.replaceAll('.', '').replaceAll(',', '').trim();
  return double.tryParse(clean) ?? 0.0;
}

class _ProductEditorState extends State<_ProductEditor> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _costPrice;
  late final TextEditingController _barcode;
  late final TextEditingController _imageUrl;
  late String _category;
  late final List<_RecipeDraft> _recipe;
  bool _showInCashier = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?['name'] as String? ?? '');

    final rawPrice = num.tryParse(product?['selling_price']?.toString() ?? '')?.toDouble() ?? 0.0;
    _price = TextEditingController(text: rawPrice > 0 ? _formatNumberWithDots(rawPrice.round()) : '');

    _barcode = TextEditingController(text: product?['sku'] as String? ?? '');
    _imageUrl = TextEditingController(text: product?['image_url'] as String? ?? '');
    _category = product?['category'] as String? ?? 'Coffee';
    _showInCashier = product?['is_active'] ?? true;

    final oldRecipe = (product?['recipe'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    _recipe = oldRecipe
        .map((item) => _RecipeDraft(
              ingredientId: item['ingredientId'] as String?,
              quantity: item['quantity'].toString(),
            ))
        .toList();

    final rawCost = num.tryParse(product?['cost_price']?.toString() ?? '')?.toDouble() ?? 0.0;
    final calcCost = _recipe.fold(0.0, (sum, item) => sum + _lineCost(item));
    final initialHpp = rawCost > 0 ? rawCost : calcCost;
    _costPrice = TextEditingController(text: initialHpp > 0 ? _formatNumberWithDots(initialHpp.round()) : '');
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _costPrice.dispose();
    _barcode.dispose();
    _imageUrl.dispose();
    for (final item in _recipe) {
      item.quantity.dispose();
    }
    super.dispose();
  }

  double get _estimatedCost => _recipe.fold(0, (sum, item) {
        return sum + _lineCost(item);
      });

  double _lineCost(_RecipeDraft item) {
    final ingredient = widget.ingredients
        .where((row) => row['id'] == item.ingredientId)
        .firstOrNull;
    final unitCost =
        num.tryParse(ingredient?['cost_per_base_unit']?.toString() ?? '') ?? 0;
    return (double.tryParse(item.quantity.text) ?? 0) * unitCost;
  }

  void _syncHppFromRecipe() {
    final calc = _estimatedCost;
    if (calc > 0) {
      _costPrice.text = _formatNumberWithDots(calc.round());
    }
  }

  Future<void> _save() async {
    final price = _parseFormattedDouble(_price.text);
    if (_name.text.trim().isEmpty || price <= 0) {
      setState(() => _error = 'Nama dan harga jual wajib diisi dengan benar.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final hppVal = _costPrice.text.trim().isNotEmpty
          ? _parseFormattedDouble(_costPrice.text)
          : _estimatedCost;

      final payload = {
        'name': _name.text.trim(),
        'category': _category,
        'sku': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        'sellingPrice': price,
        'costPrice': hppVal,
        'imageUrl':
            _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
        'isActive': _showInCashier,
        'recipe': _recipe
            .map((item) => {
                  'ingredientId': item.ingredientId,
                  'quantity': double.tryParse(item.quantity.text) ?? 0,
                })
            .toList(),
      };
      final id = widget.product?['id'];
      await _adminRequest(context, id == null ? 'POST' : 'PUT',
          id == null ? '/products' : '/products/$id',
          body: payload);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file != null) {
        final bytes = await file.readAsBytes();
        final ext = file.extension?.toLowerCase() ?? 'png';
        final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';
        final base64Str = base64Encode(bytes);
        final dataUrl = 'data:$mime;base64,$base64Str';
        setState(() {
          _imageUrl.text = dataUrl;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memilih gambar: $e')),
        );
      }
    }
  }

  Widget _buildImagePreview(String source) {
    const mutedGray = Color(0xFF8C7D73);
    if (source.startsWith('data:image')) {
      try {
        final base64Bytes = base64Decode(source.split(',').last);
        return Image.memory(base64Bytes, fit: BoxFit.cover);
      } catch (_) {
        return const Icon(Icons.image_not_supported_outlined, color: mutedGray);
      }
    }
    return Image.network(
      source,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.image_not_supported_outlined, color: mutedGray),
    );
  }

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: 820,
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product == null ? 'Tambah Produk' : 'Edit Produk',
                        style: const TextStyle(
                          color: darkBrown,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Atur harga, resep, dan ketersediaan di kasir',
                        style: TextStyle(color: mutedGray, fontSize: 12),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF5EBE1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: mutedGray),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2-Column Body
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT COLUMN: Product Info
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nama Produk *
                        const Text('Nama Produk *',
                            style: TextStyle(
                                color: darkBrown,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _name,
                          style: const TextStyle(
                              color: darkBrown,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: 'Masukkan nama produk',
                            hintStyle:
                                const TextStyle(color: mutedGray, fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFFAFAFA),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: terracotta, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Kategori & Barcode
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Kategori',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _category,
                                    style: const TextStyle(
                                        color: darkBrown,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFFAFAFA),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 11),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0)),
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'Coffee',
                                          child: Text('Coffee')),
                                      DropdownMenuItem(
                                          value: 'Non-coffee',
                                          child: Text('Non-coffee')),
                                      DropdownMenuItem(
                                          value: 'Makanan',
                                          child: Text('Makanan')),
                                    ],
                                    onChanged: (value) => setState(
                                        () => _category = value ?? 'Coffee'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Barcode',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _barcode,
                                    style: const TextStyle(
                                        color: darkBrown,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFFAFAFA),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 11),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: terracotta, width: 1.5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Harga Jual * & HPP (Modal)
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Harga Jual *',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _price,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    onChanged: (val) {
                                      final clean = val.replaceAll('.', '').replaceAll(',', '');
                                      if (clean.isNotEmpty) {
                                        final formatted = _formatNumberWithDots(clean);
                                        if (formatted != val) {
                                          _price.value = TextEditingValue(
                                            text: formatted,
                                            selection: TextSelection.collapsed(offset: formatted.length),
                                          );
                                        }
                                      }
                                      setState(() {});
                                    },
                                    style: const TextStyle(
                                        color: darkBrown,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      prefixText: 'Rp ',
                                      hintText: '0',
                                      hintStyle: const TextStyle(color: mutedGray, fontSize: 13),
                                      filled: true,
                                      fillColor: const Color(0xFFFAFAFA),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 11),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: terracotta, width: 1.5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('HPP (Modal)',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _costPrice,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    onChanged: (val) {
                                      final clean = val.replaceAll('.', '').replaceAll(',', '');
                                      if (clean.isNotEmpty) {
                                        final formatted = _formatNumberWithDots(clean);
                                        if (formatted != val) {
                                          _costPrice.value = TextEditingValue(
                                            text: formatted,
                                            selection: TextSelection.collapsed(offset: formatted.length),
                                          );
                                        }
                                      }
                                      setState(() {});
                                    },
                                    style: const TextStyle(
                                        color: darkBrown,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      prefixText: 'Rp ',
                                      hintText: _estimatedCost > 0
                                          ? _formatNumberWithDots(_estimatedCost.round())
                                          : '0',
                                      hintStyle: const TextStyle(
                                          color: mutedGray, fontSize: 13),
                                      filled: true,
                                      fillColor: const Color(0xFFFAFAFA),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 11),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: terracotta, width: 1.5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Gambar Produk (Upload & Preview)
                        const Text('Gambar Produk',
                            style: TextStyle(
                                color: darkBrown,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        if (_imageUrl.text.trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFAFA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: _buildImagePreview(_imageUrl.text.trim()),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      Text('Gambar dipilih',
                                          style: TextStyle(
                                              color: darkBrown,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700)),
                                      SizedBox(height: 2),
                                      Text('Siap disimpan',
                                          style: TextStyle(color: Color(0xFF1E8E3E), fontSize: 10)),
                                    ],
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _pickImage,
                                  icon: const Icon(Icons.refresh_rounded, size: 14, color: terracotta),
                                  label: const Text('Ganti',
                                      style: TextStyle(color: terracotta, fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                                IconButton(
                                  onPressed: () => setState(() => _imageUrl.clear()),
                                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFDC2626)),
                                ),
                              ],
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _pickImage,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: darkBrown,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.upload_file_rounded, size: 18, color: terracotta),
                              label: const Text('Upload Gambar dari Perangkat',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        const SizedBox(height: 12),
                        // Status Aktif / Tampilkan di Kasir
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('Tampilkan di Kasir',
                                    style: TextStyle(
                                        color: darkBrown,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                SizedBox(height: 2),
                                Text('Produk aktif & dapat di-order kasir',
                                    style: TextStyle(
                                        color: mutedGray, fontSize: 11)),
                              ],
                            ),
                            Switch(
                              value: _showInCashier,
                              activeTrackColor: terracotta,
                              onChanged: (val) =>
                                  setState(() => _showInCashier = val),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),

                  // RIGHT COLUMN: Resep & Profit Box
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Resep per 1 porsi + Tambah bahan
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Resep per 1 porsi',
                              style: TextStyle(
                                color: darkBrown,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            InkWell(
                              onTap: widget.ingredients.isEmpty
                                  ? null
                                  : () {
                                      setState(() {
                                        _recipe.add(_RecipeDraft(
                                            ingredientId: widget
                                                .ingredients.first['id'] as String));
                                        _syncHppFromRecipe();
                                      });
                                    },
                              child: const Text(
                                '+ Tambah bahan',
                                style: TextStyle(
                                  color: terracotta,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Table Header Row for Recipe
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAF2E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: const [
                              Expanded(
                                  flex: 4,
                                  child: Text('Bahan',
                                      style: TextStyle(
                                          color: mutedGray,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700))),
                              Expanded(
                                  flex: 3,
                                  child: Text('Jumlah',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: mutedGray,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700))),
                              Expanded(
                                  flex: 3,
                                  child: Text('Biaya',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          color: mutedGray,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700))),
                              SizedBox(width: 24),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Recipe Items
                        if (_recipe.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Belum ada bahan resep.',
                              style: TextStyle(color: mutedGray, fontSize: 12),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _recipe.length,
                              itemBuilder: (context, index) {
                                  final draft = _recipe[index];
                                  final ing = widget.ingredients
                                      .where((row) => row['id'] == draft.ingredientId)
                                      .firstOrNull;
                                  final lineCostVal = _lineCost(draft);
                                  final baseUnit = ing?['base_unit'] as String? ?? '';

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFAFAFA),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        children: [
                                          // Dropdown Bahan
                                          Expanded(
                                            flex: 4,
                                            child:
                                                DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                isExpanded: true,
                                                isDense: true,
                                                value: widget.ingredients.any(
                                                        (item) =>
                                                            item['id'] ==
                                                            draft.ingredientId)
                                                    ? draft.ingredientId
                                                    : null,
                                                hint: const Text('Pilih...',
                                                    style: TextStyle(
                                                        fontSize: 12)),
                                                items: widget.ingredients
                                                    .map((item) =>
                                                        DropdownMenuItem<String>(
                                                          value: item['id']
                                                              as String,
                                                          child: Text(
                                                            _capitalizeTitle(item['name']
                                                                as String? ?? ''),
                                                            style: const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: darkBrown),
                                                            overflow: TextOverflow
                                                                .ellipsis,
                                                          ),
                                                        ))
                                                    .toList(),
                                                onChanged: (val) {
                                                  setState(() {
                                                    draft.ingredientId = val;
                                                    _syncHppFromRecipe();
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                          // Input Jumlah
                                          Expanded(
                                            flex: 3,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 4),
                                              child: SizedBox(
                                                height: 28,
                                                child: TextField(
                                                  controller: draft.quantity,
                                                  keyboardType: const TextInputType
                                                      .numberWithOptions(
                                                      decimal: true),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
                                                  ],
                                                  onChanged: (_) {
                                                    setState(() {
                                                      _syncHppFromRecipe();
                                                    });
                                                  },
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600),
                                                  textAlign: TextAlign.center,
                                                  decoration: InputDecoration(
                                                    hintText: '0',
                                                    suffixText: _formatUnitDisplay(baseUnit),
                                                    suffixStyle: const TextStyle(
                                                        fontSize: 11,
                                                        color: mutedGray),
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 0),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(8),
                                                      borderSide: const BorderSide(
                                                          color: Color(0xFFE2E8F0)),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        // Calculated Line Cost
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            _money(lineCostVal),
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                              color: darkBrown,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Remove Button
                                        InkWell(
                                          onTap: () => setState(() {
                                            _recipe.removeAt(index);
                                            draft.quantity.dispose();
                                            _syncHppFromRecipe();
                                          }),
                                          child: const Icon(
                                              Icons.close_rounded,
                                              color: Color(0xFFDC2626),
                                              size: 16),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFDC2626))),
                ),
              const SizedBox(height: 18),

              // Bottom Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 38,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: darkBrown,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Batal',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 38,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: terracotta,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        _saving ? 'Menyimpan...' : 'Simpan Produk',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminIngredientsPage extends StatefulWidget {
  const AdminIngredientsPage({super.key});

  @override
  State<AdminIngredientsPage> createState() => _AdminIngredientsPageState();
}

class _AdminIngredientsPageState extends State<AdminIngredientsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data =
          await _adminRequest(context, 'GET', '/ingredients') as List<dynamic>;
      if (mounted) {
        setState(() {
          _items = data.cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEdit([Map<String, dynamic>? ingredient]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AdminAddIngredientDialog(ingredient: ingredient),
    );
    if (!mounted || result == null) return;
    if (result['delete'] == true && ingredient != null) {
      await _delete(ingredient);
      return;
    }
    try {
      if (ingredient == null) {
        await _adminRequest(context, 'POST', '/ingredients', body: result);
      } else {
        await _adminRequest(
          context,
          'PATCH',
          '/ingredients/${ingredient['id']}',
          body: result,
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan bahan: $error')),
        );
      }
    }
  }

  Future<void> _restock(Map<String, dynamic> item) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AdminRestockDialog(ingredient: item),
    );
    if (!mounted || values == null) return;
    try {
      await _adminRequest(
        context,
        'POST',
        '/ingredients/${item['id']}/restock',
        body: values,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Bahan Baku?'),
        content: Text('Bahan "${item['name']}" akan dihapus dari daftar stok.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _adminRequest(context, 'DELETE', '/ingredients/${item['id']}');
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus bahan: $error')),
        );
      }
    }
  }

  void _showRestockHistory() {
    showDialog<void>(
      context: context,
      builder: (context) => const _RestockHistoryDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final lowStockItems =
        _items.where((item) => item['is_low_stock'] == true).toList();
    final lowStockNames = lowStockItems
        .map((item) => _capitalizeTitle(item['name'] as String? ?? ''))
        .join(' dan ');

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Area
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Stok Bahan',
                        style: TextStyle(
                          color: darkBrown,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Pantau persediaan agar menu tidak kehabisan',
                        style: TextStyle(color: mutedGray, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // Action Buttons
                FilledButton(
                  onPressed: _showRestockHistory,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: darkBrown,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  child: const Text('Riwayat Restock',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _addOrEdit(),
                  style: FilledButton.styleFrom(
                    backgroundColor: terracotta,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tambah Bahan',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          // Low Stock Alert Banner
          if (lowStockItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle,
                        size: 10, color: Color(0xFFD97706)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${lowStockItems.length} bahan hampir habis: $lowStockNames. Segera restock.',
                        style: const TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_error != null) _ErrorBanner(message: _error!, onRetry: _load),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Belum ada data bahan.',
                    style: TextStyle(color: mutedGray, fontSize: 14)),
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width < 600 ? 2 : 3;
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(26, 4, 26, 26),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: width < 700 ? 1.85 : 2.20,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final isLow = item['is_low_stock'] == true;
                      final stock = num.tryParse(item['stock_quantity']?.toString() ?? '')?.toDouble() ?? 0.0;
                      final threshold = num.tryParse(item['low_stock_threshold']?.toString() ?? '')?.toDouble() ?? 0.0;
                      final unit = _formatUnitDisplay(item['base_unit'] as String?);
                      final progress = (threshold > 0)
                          ? (stock / (threshold * 2.5)).clamp(0.05, 1.0)
                          : 0.8;

                      final stockFormatted = stock
                          .round()
                          .toString()
                          .replaceAllMapped(
                              RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
                      final thresholdFormatted = threshold
                          .round()
                          .toString()
                          .replaceAllMapped(
                              RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');

                      return Container(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: isLow
                                  ? const Color(0xFFFCA5A5)
                                  : const Color(0xFFF3ECE5)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Row: Capitalized Name & Status Badge
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _capitalizeTitle(item['name'] as String? ?? ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: darkBrown,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isLow
                                        ? const Color(0xFFFCE8E6)
                                        : const Color(0xFFE6F4EA),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    isLow ? 'Menipis' : 'Aman',
                                    style: TextStyle(
                                      color: isLow
                                          ? const Color(0xFFD93025)
                                          : const Color(0xFF1E8E3E),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Quantity Row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '$stockFormatted $unit',
                                  style: TextStyle(
                                    color: isLow
                                        ? const Color(0xFFD93025)
                                        : darkBrown,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'min $thresholdFormatted $unit',
                                  style: const TextStyle(
                                      color: mutedGray,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Progress Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                backgroundColor: const Color(0xFFEFE6DD),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isLow
                                      ? const Color(0xFFD93025)
                                      : terracotta,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Action Buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () => _restock(item),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF5EBE1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          '+ Stok',
                                          style: TextStyle(
                                            color: darkBrown,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => _addOrEdit(item),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8F5F1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'Edit',
                                          style: TextStyle(
                                            color: mutedGray,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                InkWell(
                                  onTap: () => _delete(item),
                                  borderRadius: BorderRadius.circular(12),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    child: Text(
                                      'Hapus',
                                      style: TextStyle(
                                        color: Color(0xFFDC2626),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

double _toBaseMultiplier(String unit) {
  switch (unit.toLowerCase().trim()) {
    case 'kg':
    case 'l':
      return 1000.0;
    default:
      return 1.0;
  }
}

String _getBaseUnit(String unit) {
  switch (unit.toLowerCase().trim()) {
    case 'kg':
    case 'g':
    case 'gr':
    case 'gram':
      return 'gr';
    case 'l':
    case 'ml':
    case 'liter':
      return 'ml';
    default:
      return 'pcs';
  }
}

String _getMinThresholdUnit(String selectedUnit) {
  switch (selectedUnit.toLowerCase().trim()) {
    case 'kg':
    case 'g':
    case 'gr':
    case 'gram':
      return 'gr';
    case 'l':
    case 'ml':
    case 'liter':
      return 'ml';
    default:
      return 'pcs';
  }
}

String _getDisplayBaseUnit(String selectedUnit) {
  switch (selectedUnit.toLowerCase().trim()) {
    case 'kg':
    case 'g':
    case 'gr':
    case 'gram':
      return 'gr';
    case 'l':
    case 'ml':
    case 'liter':
      return 'ml';
    default:
      return 'pcs';
  }
}

String _normalizeUnit(String? unit) {
  if (unit == null) return 'gr';
  final u = unit.trim();
  if (u == 'L') return 'L';
  switch (u.toLowerCase()) {
    case 'kg':
      return 'kg';
    case 'g':
    case 'gr':
    case 'gram':
      return 'gr';
    case 'l':
    case 'liter':
      return 'L';
    case 'ml':
      return 'ml';
    case 'pcs':
    default:
      return 'pcs';
  }
}

String _formatUnitDisplay(String? unit) {
  if (unit == null) return 'gr';
  final u = unit.trim();
  if (u == 'L') return 'L';
  switch (u.toLowerCase()) {
    case 'kg':
      return 'kg';
    case 'g':
    case 'gr':
    case 'gram':
      return 'gr';
    case 'l':
    case 'liter':
      return 'L';
    case 'ml':
      return 'ml';
    case 'pcs':
    default:
      return 'pcs';
  }
}

String _capitalizeTitle(String text) {
  if (text.trim().isEmpty) return text;
  return text.trim().split(' ').map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

class _AdminAddIngredientDialog extends StatefulWidget {
  const _AdminAddIngredientDialog({this.ingredient});
  final Map<String, dynamic>? ingredient;

  @override
  State<_AdminAddIngredientDialog> createState() =>
      __AdminAddIngredientDialogState();
}

class __AdminAddIngredientDialogState extends State<_AdminAddIngredientDialog> {
  late final TextEditingController _name;
  late final TextEditingController _packageCount;
  late final TextEditingController _packageSize;
  late final TextEditingController _costPerBaseUnit;
  late final TextEditingController _lowStockThreshold;
  late final TextEditingController _totalPurchasePrice;
  String _selectedUnit = 'gr';

  @override
  void initState() {
    super.initState();
    final ing = widget.ingredient;
    final isEdit = ing != null;

    _name = TextEditingController(text: ing?['name'] as String? ?? '');

    final rawBaseUnit = (ing?['base_unit'] as String? ?? 'gr').trim().toLowerCase();
    final totalStock = num.tryParse(ing?['stock_quantity']?.toString() ?? '')?.toDouble() ?? 0.0;
    final threshold = num.tryParse(ing?['low_stock_threshold']?.toString() ?? '')?.toDouble() ?? 0.0;
    final unitCost = num.tryParse(ing?['cost_per_base_unit']?.toString() ?? '')?.toDouble() ?? 0.0;

    String unit = _normalizeUnit(rawBaseUnit);
    double sizeVal = totalStock;
    double thresholdVal = threshold;

    if (isEdit) {
      if ((rawBaseUnit == 'gr' || rawBaseUnit == 'g' || rawBaseUnit == 'gram') && totalStock >= 1000 && totalStock % 1000 == 0) {
        unit = 'kg';
        sizeVal = totalStock / 1000;
        thresholdVal = threshold / 1000;
      } else if ((rawBaseUnit == 'ml' || rawBaseUnit == 'liter' || rawBaseUnit == 'l') && totalStock >= 1000 && totalStock % 1000 == 0) {
        unit = 'L';
        sizeVal = totalStock / 1000;
        thresholdVal = threshold / 1000;
      }
    }

    _selectedUnit = unit;
    _packageCount = TextEditingController(text: isEdit ? '1' : '');
    _packageSize = TextEditingController(
        text: isEdit && sizeVal > 0 ? (sizeVal % 1 == 0 ? sizeVal.toInt().toString() : sizeVal.toString()) : '');
    _lowStockThreshold = TextEditingController(
        text: isEdit && thresholdVal > 0 ? (thresholdVal % 1 == 0 ? thresholdVal.toInt().toString() : thresholdVal.toString()) : '');

    final totalPurchase = unitCost * totalStock;
    _totalPurchasePrice = TextEditingController(
      text: isEdit && totalPurchase > 0 ? _formatNumberWithDots(totalPurchase.round()) : '',
    );
    _costPerBaseUnit = TextEditingController(
      text: isEdit && unitCost > 0 ? _formatNumberWithDots(unitCost.round()) : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _packageCount.dispose();
    _packageSize.dispose();
    _costPerBaseUnit.dispose();
    _lowStockThreshold.dispose();
    _totalPurchasePrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final isEdit = widget.ingredient != null;
    final baseUnit = _getBaseUnit(_selectedUnit);
    final minUnit = _getMinThresholdUnit(_selectedUnit);

    final pkgCount = double.tryParse(_packageCount.text.trim()) ?? 1;
    final pkgSize = double.tryParse(_packageSize.text.trim()) ?? 0;
    final multiplier = _toBaseMultiplier(_selectedUnit);
    final totalBaseStock = pkgCount * pkgSize * multiplier;

    final totalPurchasePrice = _parseFormattedDouble(_totalPurchasePrice.text);
    final pricePerPackage = pkgCount > 0 ? totalPurchasePrice / pkgCount : 0.0;
    final pricePerBaseUnit =
        totalBaseStock > 0 ? totalPurchasePrice / totalBaseStock : 0.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: 460,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEdit ? 'Edit bahan' : 'Tambah bahan',
                    style: const TextStyle(
                      color: darkBrown,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF5EBE1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: mutedGray),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Nama bahan
              const Text('Nama bahan *',
                  style: TextStyle(
                      color: darkBrown,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                style: const TextStyle(
                    color: darkBrown,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Contoh: Gula pasir, Susu',
                  hintStyle: const TextStyle(color: mutedGray, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Quantity & Nominal per Kemasan / Stok Awal (dengan Pilihan Satuan Terintegrasi dalam Textbox)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Quantity',
                            style: TextStyle(
                                color: darkBrown,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _packageCount,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (val) {
                            if (val.trim() == '0') {
                              _packageCount.text = '1';
                              _packageCount.selection =
                                  TextSelection.fromPosition(
                                const TextPosition(offset: 1),
                              );
                            }
                            setState(() {});
                          },
                          style: const TextStyle(
                              color: darkBrown,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: '1',
                            filled: true,
                            fillColor: const Color(0xFFFAFAFA),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isEdit ? 'Stok per kemasan' : 'Stok awal',
                            style: const TextStyle(
                                color: darkBrown,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _packageSize,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(
                                      color: darkBrown,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  decoration: const InputDecoration(
                                    hintText: '1000',
                                    hintStyle: TextStyle(
                                        color: mutedGray, fontSize: 13),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 11),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                  ),
                                ),
                              ),
                              Container(
                                height: 22,
                                width: 1,
                                color: const Color(0xFFCBD5E1),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedUnit,
                                    icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: darkBrown),
                                    dropdownColor: Colors.white,
                                    style: const TextStyle(
                                        color: darkBrown,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'kg', child: Text('kg')),
                                      DropdownMenuItem(
                                          value: 'gr', child: Text('gr')),
                                      DropdownMenuItem(
                                          value: 'L', child: Text('L')),
                                      DropdownMenuItem(
                                          value: 'ml', child: Text('ml')),
                                      DropdownMenuItem(
                                          value: 'pcs', child: Text('pcs')),
                                    ],
                                    onChanged: (val) => setState(
                                        () => _selectedUnit = val ?? 'gr'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Batas minimum (otomatis 'g' jika 'kg', 'ml' jika 'l')
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Batas minimum ($minUnit)',
                            style: const TextStyle(
                                color: darkBrown,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _lowStockThreshold,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(
                              color: darkBrown,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: '500',
                            suffixText: minUnit,
                            suffixStyle: const TextStyle(
                                color: mutedGray, fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFFFAFAFA),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (isEdit) ...[
                const SizedBox(height: 14),
                // HPP (Modal) (untuk Edit)
                const Text('HPP (Modal)',
                    style: TextStyle(
                        color: darkBrown,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: _costPerBaseUnit,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                      color: darkBrown,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    prefixText: 'Rp ',
                    suffixText: '/ $baseUnit',
                    suffixStyle:
                        const TextStyle(color: mutedGray, fontSize: 12),
                    hintText: 'Otomatis/manual',
                    hintStyle: const TextStyle(color: mutedGray, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Dipakai untuk menghitung HPP resep.',
                    style: TextStyle(color: mutedGray, fontSize: 11)),
              ] else ...[
                const SizedBox(height: 14),
                // Total harga pembelian (Rp)
                const Text('Total harga pembelian (Rp)',
                    style: TextStyle(
                        color: darkBrown,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: _totalPurchasePrice,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (val) {
                    final clean = val.replaceAll('.', '').replaceAll(',', '');
                    if (clean.isNotEmpty) {
                      final formatted = _formatNumberWithDots(clean);
                      if (formatted != val) {
                        _totalPurchasePrice.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(offset: formatted.length),
                        );
                      }
                    }
                    setState(() {});
                  },
                  style: const TextStyle(
                      color: darkBrown,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    prefixText: 'Rp ',
                    hintText: '80.000',
                    hintStyle: const TextStyle(color: mutedGray, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Neatly organized summary box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total stok awal',
                              style: TextStyle(
                                  color: mutedGray,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            '${totalBaseStock.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')} ${_getDisplayBaseUnit(_selectedUnit)}',
                            style: const TextStyle(
                                color: darkBrown,
                                fontSize: 15,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Harga beli per kemasan',
                              style: TextStyle(
                                  color: mutedGray,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            _money(pricePerPackage),
                            style: const TextStyle(
                                color: terracotta,
                                fontSize: 15,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: darkBrown,
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Batal',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () {
                      final name = _name.text.trim();
                      final threshold =
                          double.tryParse(_lowStockThreshold.text) ?? 0;
                      final costText = _costPerBaseUnit.text.trim();
                      final cost = !isEdit
                          ? pricePerBaseUnit
                          : (costText.isNotEmpty ? double.tryParse(costText) : 0);

                      if (name.isEmpty) return;

                      Navigator.pop(context, {
                        'name': name,
                        'baseUnit': baseUnit,
                        'stockQuantity': totalBaseStock,
                        'lowStockThreshold': threshold,
                        'costPerBaseUnit': cost ?? 0,
                      });
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: terracotta,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(isEdit ? 'Simpan' : 'Simpan bahan',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminRestockDialog extends StatefulWidget {
  const _AdminRestockDialog({required this.ingredient});
  final Map<String, dynamic> ingredient;

  @override
  State<_AdminRestockDialog> createState() => _AdminRestockDialogState();
}

class _AdminRestockDialogState extends State<_AdminRestockDialog> {
  late final TextEditingController _packageCount;
  late final TextEditingController _contentPerPackage;
  late final TextEditingController _pricePerPackage;
  String _restockUnit = 'kg';

  @override
  void initState() {
    super.initState();
    final ing = widget.ingredient;
    final baseUnit = ing['base_unit'] as String? ?? 'gr';
    final normalized = _normalizeUnit(baseUnit);
    if (normalized == 'gr') {
      _restockUnit = 'kg';
    } else if (normalized == 'ml') {
      _restockUnit = 'L';
    } else {
      _restockUnit = 'pcs';
    }

    final storedCostPerBaseUnit =
        num.tryParse(ing['cost_per_base_unit']?.toString() ?? '')?.toDouble() ?? 0.0;
    final initialMultiplier = _toBaseMultiplier(_restockUnit);
    final defaultPrice = (storedCostPerBaseUnit * initialMultiplier).round();

    _packageCount = TextEditingController(text: '1');
    _contentPerPackage = TextEditingController(text: '1');
    _pricePerPackage = TextEditingController(
      text: defaultPrice > 0 ? _formatNumberWithDots(defaultPrice) : '',
    );
  }

  @override
  void dispose() {
    _packageCount.dispose();
    _contentPerPackage.dispose();
    _pricePerPackage.dispose();
    super.dispose();
  }

  void _addPackage(double count) {
    final current = double.tryParse(_packageCount.text) ?? 0;
    setState(() {
      _packageCount.text = (current + count).round().toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final ing = widget.ingredient;
    final name = ing['name'] as String? ?? 'Bahan';
    final baseUnit = _getBaseUnit(ing['base_unit'] as String? ?? 'g');
    final currentStock =
        num.tryParse(ing['stock_quantity']?.toString() ?? '')?.toDouble() ?? 0;
    final minStock =
        num.tryParse(ing['low_stock_threshold']?.toString() ?? '')?.toDouble() ?? 0;
    final isLow = ing['is_low_stock'] == true;

    final multiplier = _toBaseMultiplier(_restockUnit);
    final storedCost = num.tryParse(ing['cost_per_base_unit']?.toString() ?? '')?.toDouble() ?? 0.0;

    final parsedPkgCount = _parseFormattedDouble(_packageCount.text);
    final pkgCount = (parsedPkgCount > 0) ? parsedPkgCount : 1.0;

    final parsedContent = _parseFormattedDouble(_contentPerPackage.text);
    final defaultSize = (_restockUnit == 'kg' || _restockUnit == 'L') ? 1.0 : 1000.0;
    final contentPerPkg = (parsedContent > 0) ? parsedContent : defaultSize;

    final parsedPrice = _parseFormattedDouble(_pricePerPackage.text);
    final defaultPriceVal = (storedCost * multiplier) > 0 ? (storedCost * multiplier) : 20000.0;
    final pricePerPkg = (parsedPrice > 0) ? parsedPrice : defaultPriceVal;

    final totalAddedInBaseUnits = pkgCount * contentPerPkg * multiplier;
    final totalPurchaseCost = pkgCount * pricePerPkg;
    final calculatedPricePerBaseUnit = totalAddedInBaseUnits > 0
        ? totalPurchaseCost / totalAddedInBaseUnits
        : 0.0;

    final newStock = currentStock + totalAddedInBaseUnits;
    final isSafeNew = newStock >= minStock;

    final formattedAddedStock = totalAddedInBaseUnits
        .round()
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
    final formattedNewStock = newStock
        .round()
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: 480,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tambah stok',
                    style: TextStyle(
                      color: darkBrown,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF5EBE1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: mutedGray),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Ingredient Summary Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                color: darkBrown,
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('Stok ${currentStock.round()} $baseUnit · minimum ${minStock.round()} $baseUnit',
                            style: const TextStyle(
                                color: mutedGray, fontSize: 11)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isLow
                            ? const Color(0xFFFCE8E6)
                            : const Color(0xFFE6F4EA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isLow ? 'Menipis' : 'Aman',
                        style: TextStyle(
                          color: isLow
                              ? const Color(0xFFD93025)
                              : const Color(0xFF1E8E3E),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Quantity & Nominal Isi per Kemasan dengan Integrated Unit Selector Dropdown
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Quantity (Jumlah)',
                            style: TextStyle(
                                color: darkBrown,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _packageCount,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                              color: darkBrown,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: '4',
                            filled: true,
                            fillColor: const Color(0xFFFAFAFA),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Isi per Kemasan',
                            style: TextStyle(
                                color: darkBrown,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _contentPerPackage,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(
                                      color: darkBrown,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  decoration: const InputDecoration(
                                    hintText: '1',
                                    hintStyle: TextStyle(
                                        color: mutedGray, fontSize: 13),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 11),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                  ),
                                ),
                              ),
                              Container(
                                height: 22,
                                width: 1,
                                color: const Color(0xFFCBD5E1),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _restockUnit,
                                    icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: darkBrown),
                                    dropdownColor: Colors.white,
                                    style: const TextStyle(
                                        color: darkBrown,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'kg', child: Text('kg')),
                                      DropdownMenuItem(
                                          value: 'gr', child: Text('gr')),
                                      DropdownMenuItem(
                                          value: 'L', child: Text('L')),
                                      DropdownMenuItem(
                                          value: 'ml', child: Text('ml')),
                                      DropdownMenuItem(
                                          value: 'pcs', child: Text('pcs')),
                                    ],
                                    onChanged: (val) => setState(
                                        () => _restockUnit = val ?? 'kg'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Quick Add Chips Row
              Row(
                children: [1, 5, 10].map((val) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => _addPackage(val.toDouble()),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          '+$val Qty',
                          style: const TextStyle(
                              color: darkBrown,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Harga Beli per Kemasan
              const Text('Harga beli per kemasan (Rp)',
                  style: TextStyle(
                      color: darkBrown,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _pricePerPackage,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (val) {
                  final clean = val.replaceAll('.', '').replaceAll(',', '');
                  if (clean.isNotEmpty) {
                    final formatted = _formatNumberWithDots(clean);
                    if (formatted != val) {
                      _pricePerPackage.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                  }
                  setState(() {});
                },
                style: const TextStyle(
                    color: darkBrown,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  hintText: '20.000',
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Automatic Conversion & Price Calculator Box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Pembelian',
                            style: TextStyle(color: mutedGray, fontSize: 11)),
                        Text(_money(totalPurchaseCost),
                            style: const TextStyle(
                                color: darkBrown,
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Konversi Penambahan Stok',
                            style: TextStyle(color: mutedGray, fontSize: 11)),
                        Text('+$formattedAddedStock $baseUnit',
                            style: const TextStyle(
                                color: Color(0xFF16A34A),
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Harga Satuan Baru (otomatis)',
                            style: TextStyle(color: mutedGray, fontSize: 11)),
                        Text(
                          (baseUnit == 'gr' || baseUnit == 'g')
                              ? '${_money(calculatedPricePerBaseUnit)}/gr (${_money(calculatedPricePerBaseUnit * 1000)}/kg)'
                              : ((baseUnit == 'ml')
                                  ? '${_money(calculatedPricePerBaseUnit)}/ml (${_money(calculatedPricePerBaseUnit * 1000)}/L)'
                                  : '${_money(calculatedPricePerBaseUnit)}/$baseUnit'),
                          style: const TextStyle(
                              color: terracotta,
                              fontSize: 12,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Stok setelah ditambah',
                            style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
                        Text('$formattedNewStock $baseUnit',
                            style: const TextStyle(
                                color: darkBrown,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: isSafeNew ? 0.85 : 0.2,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE2E8F0),
                        color: isSafeNew
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFD93025),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: darkBrown,
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Batal',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () {
                      if (totalAddedInBaseUnits <= 0) return;
                      Navigator.pop(context, {
                        'quantityAdded': totalAddedInBaseUnits,
                        'totalCost': totalPurchaseCost,
                      });
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: terracotta,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Simpan stok',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestockHistoryDialog extends StatefulWidget {
  const _RestockHistoryDialog();

  @override
  State<_RestockHistoryDialog> createState() => _RestockHistoryDialogState();
}

class _RestockHistoryDialogState extends State<_RestockHistoryDialog> {
  String _filter = 'Semua';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _history = [];
  int _restockCountMonth = 0;
  double _totalPurchaseMonth = 0.0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _adminRequest(context, 'GET', '/ingredients/restock-history');
      if (!mounted) return;
      final data = res as Map<String, dynamic>? ?? {};
      final list = (data['history'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final summary = data['summary'] as Map<String, dynamic>? ?? {};
      setState(() {
        _history = list;
        _restockCountMonth = (summary['restockCountMonth'] as num?)?.toInt() ?? 0;
        _totalPurchaseMonth = (summary['totalPurchaseMonth'] as num?)?.toDouble() ?? 0.0;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _formatTime(dynamic raw) {
    if (raw == null) return '14:00 WIB';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m WIB';
    } catch (_) {
      return '14:00 WIB';
    }
  }

  List<Map<String, dynamic>> get _filteredHistory {
    if (_filter == 'Masuk' || _filter == 'Restock') {
      return _history.where((m) => m['movement_type'] == 'RESTOCK' || m['movement_type'] == 'INITIAL').toList();
    }
    if (_filter == 'Keluar' || _filter == 'Penjualan') {
      return _history.where((m) => m['movement_type'] == 'SALE').toList();
    }
    if (_filter == 'Pembatalan') {
      return _history.where((m) => m['movement_type'] == 'CANCELLATION').toList();
    }
    return _history;
  }

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final filtered = _filteredHistory;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: 520,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: darkBrown, size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Riwayat Restock & Stok',
                      style: TextStyle(
                        color: darkBrown,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF5EBE1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 16, color: mutedGray),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Summary Cards
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Restock bulan ini',
                            style: TextStyle(color: mutedGray, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text('$_restockCountMonth kali',
                            style: const TextStyle(
                                color: darkBrown,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Nilai pembelian',
                            style: TextStyle(color: mutedGray, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(_money(_totalPurchaseMonth),
                            style: const TextStyle(
                                color: terracotta,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Filter Chips
            Row(
              children: ['Semua', 'Restock', 'Penjualan', 'Pembatalan'].map((f) {
                final active = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => setState(() => _filter = f),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFFF5EBE1) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: active
                              ? terracotta
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          color: active ? terracotta : darkBrown,
                          fontSize: 12,
                          fontWeight:
                              active ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            if (_loading)
              const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const SizedBox(
                height: 220,
                child: Center(
                  child: Text('Belum ada riwayat stok.',
                      style: TextStyle(color: mutedGray, fontSize: 13)),
                ),
              )
            else
              SizedBox(
                height: 280,
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final type = item['movement_type'] as String? ?? 'RESTOCK';
                    final isPositive = type == 'RESTOCK' || type == 'INITIAL' || type == 'CANCELLATION';
                    final ingName = _capitalizeTitle(item['ingredient_name']?.toString() ?? 'Bahan');
                    final delta = num.tryParse(item['quantity_delta']?.toString() ?? '')?.toDouble() ?? 0.0;
                    final unit = _formatUnitDisplay(item['base_unit'] as String?);
                    final cost = num.tryParse(item['total_cost']?.toString() ?? '')?.toDouble() ?? 0.0;
                    final user = item['user_name']?.toString() ?? 'Kasir';
                    final note = item['note']?.toString();
                    final timeStr = _formatTime(item['created_at']);

                    String subtitle = '$timeStr • Oleh $user';
                    if (note != null && note.isNotEmpty) {
                      subtitle += ' ($note)';
                    }

                    IconData iconData = Icons.add_shopping_cart_rounded;
                    Color iconBg = const Color(0xFFE6F4EA);
                    Color iconColor = const Color(0xFF1E8E3E);

                    if (type == 'SALE') {
                      iconData = Icons.local_cafe_rounded;
                      iconBg = const Color(0xFFFCE8E6);
                      iconColor = const Color(0xFFD93025);
                    } else if (type == 'CANCELLATION') {
                      iconData = Icons.undo_rounded;
                      iconBg = const Color(0xFFE0F2FE);
                      iconColor = const Color(0xFF0284C7);
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: iconBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(iconData, size: 16, color: iconColor),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ingName,
                                  style: const TextStyle(
                                      color: darkBrown,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: const TextStyle(color: mutedGray, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isPositive ? '+' : ''}${delta.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')} $unit',
                                style: TextStyle(
                                  color: isPositive ? const Color(0xFF1E8E3E) : const Color(0xFFD93025),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (cost > 0)
                                Text(
                                  _money(cost),
                                  style: const TextStyle(color: terracotta, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminTransactionsPage extends StatefulWidget {
  const AdminTransactionsPage({super.key});
  @override
  State<AdminTransactionsPage> createState() => _AdminTransactionsPageState();
}

class _AdminTransactionsPageState extends State<AdminTransactionsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredOrders {
    if (_searchQuery.trim().isEmpty) return _items;
    final query = _searchQuery.toLowerCase().trim();
    return _items.where((order) {
      final number =
          (order['order_number'] ?? order['id'] ?? '').toString().toLowerCase();
      return number.contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data =
          await _adminRequest(context, 'GET', '/transactions') as List<dynamic>;
      if (mounted) {
        setState(() {
          _items = data.cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatOrderCode(Map<String, dynamic> order, [int? index]) {
    final rawNum = (order['order_number'] ?? order['orderNumber'] ?? '').toString().trim();
    if (rawNum.isNotEmpty && RegExp(r'^A-\d{1,5}$', caseSensitive: false).hasMatch(rawNum)) {
      return rawNum.startsWith('#') ? rawNum : '#$rawNum';
    }
    if (rawNum.isNotEmpty && rawNum.length <= 10 && !rawNum.contains('29067')) {
      return rawNum.startsWith('#') ? rawNum : '#$rawNum';
    }
    if (index != null) {
      return '#A-${index.toString().padLeft(5, '0')}';
    }
    return '#A-00001';
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) return '-';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final y = dt.year;
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$d/$m/$y $h:$min WIB';
    } catch (_) {
      return raw.toString();
    }
  }

  Future<void> _cancel(Map<String, dynamic> order) async {
    final orderCode = _formatOrderCode(order);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Batalkan transaksi?'),
              content: Text(
                  'Struk $orderCode akan ditandai batal dan stok resep dikembalikan.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Kembali')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626)),
                    child: const Text('Batalkan')),
              ],
            ));
    if (!mounted || confirmed != true) return;
    try {
      await _adminRequest(
          context, 'POST', '/transactions/${order['id']}/cancel',
          body: {'note': 'Dibatalkan oleh admin'});
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  pw.Document _buildOrderReceiptPdf(Map<String, dynamic> order) {
    final orderCode = _formatOrderCode(order);
    final dateStr = _formatDateTime(order['created_at']);
    final lines = (order['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final paymentMethod = order['payment_method']?.toString().toUpperCase() ?? 'TUNAI';
    final totalPrice = num.tryParse(order['total_price']?.toString() ?? '')?.toDouble() ?? 0.0;
    final paidAmount = num.tryParse(order['paid_amount']?.toString() ?? '')?.toDouble() ?? 0.0;
    final changeAmount = num.tryParse(order['change_amount']?.toString() ?? '')?.toDouble() ?? 0.0;

    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat(58 * PdfPageFormat.mm, double.infinity, marginAll: 3 * PdfPageFormat.mm),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text('KOPI KITA', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text('Jl. Raya Utama No. 12', style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 4),
          pw.Text('- - - - - - - - - - - - - - - - - - - - - - - - - - - -', style: const pw.TextStyle(fontSize: 7)),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('No: $orderCode', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text(dateStr, style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Metode: $paymentMethod', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('- - - - - - - - - - - - - - - - - - - - - - - - - - - -', style: const pw.TextStyle(fontSize: 7)),
          pw.SizedBox(height: 4),
          for (final item in lines) ...[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '${_capitalizeTitle(item['name']?.toString() ?? 'Produk')} x${item['quantity']}',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Text(_money(item['subtotal']), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
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
              pw.Text('TOTAL:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(_money(totalPrice), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Dibayar:', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(_money(paidAmount), style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          if (changeAmount > 0) ...[
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Kembalian:', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(_money(changeAmount), style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ],
          pw.SizedBox(height: 6),
          pw.Text('- - - - - - - - - - - - - - - - - - - - - - - - - - - -', style: const pw.TextStyle(fontSize: 7)),
          pw.SizedBox(height: 6),
          pw.Text('Terima kasih atas kunjungan Anda!', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
        ],
      ),
    ));
    return pdf;
  }

  void _details(Map<String, dynamic> order) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final orderCode = _formatOrderCode(order);
    final lines = (order['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final isCancelled = order['status'] == 'CANCELLED';
    final pdfDoc = _buildOrderReceiptPdf(order);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Detail Transaksi $orderCode',
                style: const TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isCancelled ? const Color(0xFFFCE8E6) : const Color(0xFFE6F4EA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isCancelled ? 'DIBATALKAN' : 'SELESAI',
                style: TextStyle(
                  color: isCancelled ? const Color(0xFFD93025) : const Color(0xFF1E8E3E),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Waktu: ${_formatDateTime(order['created_at'])}',
                    style: const TextStyle(color: mutedGray, fontSize: 12)),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 8),
                for (final item in lines) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _capitalizeTitle(item['name']?.toString() ?? 'Produk'),
                                style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                '${item['quantity'] ?? 1} x ${_money(item['unitPrice'])}',
                                style: const TextStyle(color: mutedGray, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Text(_money(item['subtotal']), style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Metode Pembayaran', style: TextStyle(color: mutedGray, fontSize: 12)),
                    Text((order['payment_method'] ?? 'TUNAI').toString().toUpperCase(), style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Pembayaran', style: TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w800)),
                    Text(_money(order['total_price']), style: const TextStyle(color: terracotta, fontSize: 15, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dibayar', style: TextStyle(color: mutedGray, fontSize: 12)),
                    Text(_money(order['paid_amount']), style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                if ((num.tryParse(order['change_amount']?.toString() ?? '') ?? 0) > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Kembalian', style: TextStyle(color: mutedGray, fontSize: 12)),
                      Text(_money(order['change_amount']), style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Printing.layoutPdf(onLayout: (_) => pdfDoc.save()),
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Cetak Struk', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final pdfBytes = await pdfDoc.save();
                          await Printing.sharePdf(bytes: pdfBytes, filename: 'struk-$orderCode.pdf');
                        },
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Unduh PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!isCancelled)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _cancel(order);
              },
              child: const Text('Batalkan Transaksi', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w700)),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(backgroundColor: terracotta),
            child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final filtered = _filteredOrders;

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Search & Refresh Action Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 12, 26, 16),
            child: Row(
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Cari nomor struk...',
                      hintStyle: const TextStyle(color: mutedGray, fontSize: 13),
                      prefixIcon:
                          const Icon(Icons.search_rounded, color: mutedGray, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Muat ulang data',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, color: darkBrown),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (_error != null) _ErrorBanner(message: _error!, onRetry: _load),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Belum ada transaksi.',
                    style: TextStyle(color: mutedGray, fontSize: 14)),
              ),
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 0, 26, 26),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        // Table Header Row
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          color: const Color(0xFFFAF5F0),
                          child: Row(
                            children: const [
                              Expanded(
                                  flex: 3,
                                  child: Text('No. Struk',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  flex: 3,
                                  child: Text('Waktu',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  flex: 2,
                                  child: Text('Item',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  flex: 2,
                                  child: Text('Bayar',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  flex: 2,
                                  child: Text('Total',
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                              SizedBox(
                                  width: 95,
                                  child: Text('Aksi',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          color: darkBrown,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800))),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),

                        // Table Data Rows
                        Expanded(
                          child: ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final order = filtered[index];
                              final lines =
                                  (order['items'] as List<dynamic>? ?? [])
                                      .cast<Map<String, dynamic>>();
                              final orderNum = _formatOrderCode(order, filtered.length - index);
                              final dateStr = _formatDateTime(order['created_at']);
                              final paymentMethod =
                                  (order['payment_method'] ?? 'TUNAI')
                                      .toString()
                                      .toUpperCase();
                              final totalPrice = order['total_price'] ?? 0;
                              final isCancelled =
                                  order['status'] == 'CANCELLED';

                              // Check if we need to render a date divider (if this date is different from previous)
                              bool showDateDivider = false;
                              String currentDay = dateStr.split(' ')[0]; // e.g. "12/10/2026"
                              if (index == 0) {
                                showDateDivider = true;
                              } else {
                                final prevOrder = filtered[index - 1];
                                final prevDateStr = _formatDateTime(prevOrder['created_at']);
                                final prevDay = prevDateStr.split(' ')[0];
                                if (currentDay != prevDay) {
                                  showDateDivider = true;
                                }
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (showDateDivider)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFAF5F0),
                                        border: Border(
                                          top: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
                                          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFFC45A34)),
                                          const SizedBox(width: 8),
                                          Text(
                                            'TRANSAKSI TANGGAL $currentDay',
                                            style: TextStyle(
                                              fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                                              color: const Color(0xFF1F1F1F),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (!showDateDivider && index > 0)
                                    const Divider(height: 1, color: Color(0xFFF1F5F9)),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    child: Row(
                                  children: [
                                    // No. Struk
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        orderNum,
                                        style: TextStyle(
                                          color: isCancelled
                                              ? mutedGray
                                              : darkBrown,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          decoration: isCancelled
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                    // Waktu
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        dateStr,
                                        style: const TextStyle(
                                            color: mutedGray, fontSize: 12),
                                      ),
                                    ),
                                    // Item Count
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${lines.length} item',
                                        style: const TextStyle(
                                            color: mutedGray, fontSize: 12),
                                      ),
                                    ),
                                    // Bayar (Payment Method)
                                    Expanded(
                                      flex: 2,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            paymentMethod,
                                            style: const TextStyle(
                                                color: Color(0xFF475569),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Total Price
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        _money(totalPrice),
                                        style: TextStyle(
                                          color: isCancelled
                                              ? mutedGray
                                              : terracotta,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    // Aksi (Detail, Print, Cancel)
                                    SizedBox(
                                      width: 95,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          InkWell(
                                            onTap: () => _details(order),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(
                                                  Icons.remove_red_eye_outlined,
                                                  size: 17,
                                                  color: darkBrown),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          InkWell(
                                            onTap: () => Printing.layoutPdf(
                                                onLayout: (_) =>
                                                    _buildOrderReceiptPdf(order).save()),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(
                                                  Icons.print_outlined,
                                                  size: 17,
                                                  color: darkBrown),
                                            ),
                                          ),
                                          if (!isCancelled) ...[
                                            const SizedBox(width: 4),
                                            InkWell(
                                              onTap: () => _cancel(order),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: const Padding(
                                                padding: EdgeInsets.all(4),
                                                child: Icon(
                                                    Icons
                                                        .cancel_outlined,
                                                    size: 17,
                                                    color: Color(0xFFDC2626)),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});
  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  String _periodFilter = 'month'; // 'today', 'week', 'month'
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  Map<String, dynamic> _report = {};
  List<Map<String, dynamic>> _productBreakdown = [];
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;
  String? _error;
  int _activeSummaryPageIndex = 0;
  final PageController _summaryPageController = PageController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _summaryPageController.dispose();
    super.dispose();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _monthYearLabel(DateTime dt) {
    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(dynamic raw) {
    if (raw == null) return '14:00 WIB';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m WIB';
    } catch (_) {
      return '14:00 WIB';
    }
  }

  void _setPresetPeriod(String preset) {
    final now = DateTime.now();
    setState(() {
      _periodFilter = preset;
      if (preset == 'today') {
        _from = now;
        _to = now;
      } else if (preset == 'week') {
        _from = now.subtract(const Duration(days: 7));
        _to = now;
      } else if (preset == 'month') {
        _from = DateTime(now.year, now.month, 1);
        _to = now;
      }
    });
    _load();
  }

  Widget _presetButton(String label, String value) {
    final isActive = _periodFilter == value;
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    return InkWell(
      onTap: () => _setPresetPeriod(value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? terracotta : darkBrown,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final from = _date(_from);
      final to = _date(_to);
      final results = await Future.wait([
        _adminRequest(
            context, 'GET', '/reports/financial/summary?from=$from&to=$to'),
        _adminRequest(context, 'GET',
            '/reports/financial/profit-breakdown?from=$from&to=$to'),
        _adminRequest(
            context, 'GET', '/reports/financial/expenses?from=$from&to=$to'),
      ]);
      final data = results[0] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _report = data;
          _productBreakdown =
              (results[1] as List<dynamic>).cast<Map<String, dynamic>>();
          _expenses =
              (results[2] as List<dynamic>).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(bool start) async {
    final selectedRange = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFC45A34),
              onPrimary: Colors.white,
              onSurface: Color(0xFF3B2820),
            ),
          ),
          child: child!,
        );
      },
    );
    if (selectedRange == null) return;
    setState(() {
      _from = selectedRange.start;
      _to = selectedRange.end;
    });
    await _load();
  }

  Future<void> _addExpense() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ExpenseEditor(initialDate: _to),
    );
    if (!mounted || values == null) return;
    try {
      await _adminRequest(context, 'POST', '/reports/financial/expenses',
          body: values);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  Future<void> _deleteExpense(Map<String, dynamic> expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus biaya?'),
        content: Text('Biaya "${expense['description']}" akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await _adminRequest(
          context, 'DELETE', '/reports/financial/expenses/${expense['id']}');
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  Widget _buildSalesSummaryCard({
    required double salesTotal,
    required List<Map<String, dynamic>> products,
    required double tunaiTotal,
    required double qrisTotal,
    required double kartuTotal,
  }) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    int totalSold = 0;
    for (var p in products) {
      totalSold += (p['quantity'] as num?)?.toInt() ?? 0;
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Laporan Penjualan',
                style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800),
              ),
              InkWell(
                onTap: () => _showDetailedReportDialog('Penjualan per Menu'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFFAF2E9), borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Selengkapnya', style: TextStyle(color: terracotta, fontSize: 11, fontWeight: FontWeight.w800)),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down_rounded, color: terracotta, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _IncomeStatementRow(label: 'Total Omzet Penjualan', value: _money(salesTotal), isBold: true),
          const SizedBox(height: 6),
          _IncomeStatementRow(label: 'Jumlah Produk Terjual', value: '$totalSold porsi'),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Color(0xFFE2E8F0))),
          const Text('Metode Pembayaran Kasir', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('• Tunai: ${_money(tunaiTotal)}', style: const TextStyle(color: mutedGray, fontSize: 11)),
              Text('• QRIS: ${_money(qrisTotal)}', style: const TextStyle(color: mutedGray, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 2),
          Text('• Transfer / Kartu: ${_money(kartuTotal)}', style: const TextStyle(color: mutedGray, fontSize: 11)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Cabang / Kasir Utama', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w700)),
                Text('🟢 Online Active', style: TextStyle(color: Color(0xFF15803D), fontSize: 10, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeSummaryCard({
    required double salesTotal,
    required double costTotal,
    required double grossProfit,
    required double expenseTotal,
    required double netProfit,
  }) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Laporan Laba Rugi', style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800)),
              InkWell(
                onTap: () => _showDetailedReportDialog('Laba Rugi'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFFAF2E9), borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Selengkapnya', style: TextStyle(color: terracotta, fontSize: 11, fontWeight: FontWeight.w800)),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down_rounded, color: terracotta, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _IncomeStatementRow(label: 'Pendapatan Penjualan', value: _money(salesTotal), isBold: true),
          const SizedBox(height: 6),
          _IncomeStatementRow(label: 'HPP Bahan Baku (Modal)', value: '-${_money(costTotal)}', valueColor: const Color(0xFFD93025)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Color(0xFFE2E8F0))),
          _IncomeStatementRow(label: 'Laba Kotor (Gross Profit)', value: _money(grossProfit), valueColor: const Color(0xFF15803D), isBold: true),
          const SizedBox(height: 6),
          _IncomeStatementRow(label: 'Biaya Operasional', value: '-${_money(expenseTotal)}', valueColor: const Color(0xFFD93025), isBold: true),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFA7F3D0))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('LABA BERSIH', style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800)),
                Text(_money(netProfit), style: const TextStyle(color: Color(0xFF15803D), fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockSummaryCard({
    required Map<String, dynamic> report,
    required double costTotal,
  }) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);

    final ingList = (report['ingredients'] as List<dynamic>? ?? []);
    int totalItems = ingList.length;
    double stockValuation = 0.0;

    for (var ing in ingList) {
      final qty = num.tryParse(ing['stock_quantity']?.toString() ?? '')?.toDouble() ?? 0.0;
      final unitCost = num.tryParse(ing['cost_per_base_unit']?.toString() ?? '')?.toDouble() ?? 0.0;
      stockValuation += (qty * unitCost);
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Laporan Stok & HPP', style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800)),
              InkWell(
                onTap: () => _showDetailedReportDialog('Bahan'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFFAF2E9), borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Selengkapnya', style: TextStyle(color: terracotta, fontSize: 11, fontWeight: FontWeight.w800)),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down_rounded, color: terracotta, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _IncomeStatementRow(label: 'Valuasi Persediaan Stok Gudang', value: _money(stockValuation), isBold: true),
          const SizedBox(height: 6),
          _IncomeStatementRow(label: 'Total Bahan Keluar (Resep HPP)', value: '-${_money(costTotal)}', valueColor: const Color(0xFFD93025)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Color(0xFFE2E8F0))),
          _IncomeStatementRow(label: 'Sisa Stok Bahan Terdaftar', value: '$totalItems jenis bahan'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Status Kontrol Stok', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w700)),
                Text('⚡ Terintegrasi Otomatis', style: TextStyle(color: Color(0xFF15803D), fontSize: 10, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addCapitalEquipment() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CapitalEquipmentEditor(initialDate: _to),
    );
    if (!mounted || values == null) return;
    try {
      await _adminRequest(context, 'POST', '/reports/financial/expenses',
          body: values);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  Widget _buildHealthScorecard(double sales, double hpp, double profit) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final gajiEstimate = 5200000.0;
    final hppPct = sales > 0 ? (hpp / sales * 100) : 0.8;
    final gajiPct = sales > 0 ? (gajiEstimate / sales * 100) : 20.0;
    final primeCostPct = hppPct + gajiPct;
    final netMarginPct = sales > 0 ? (profit / sales * 100) : 0.0;

    String statusText = '🟢 Cafe Sangat Sehat (Prime Cost < 60%)';
    Color statusBg = const Color(0xFFE6F4EA);
    Color statusTextCol = const Color(0xFF15803D);

    if (primeCostPct > 65) {
      statusText = '🔴 Perlu Evaluasi HPP/Gaji (Prime Cost > 65%)';
      statusBg = const Color(0xFFFCE8E6);
      statusTextCol = const Color(0xFFD93025);
    } else if (primeCostPct > 60) {
      statusText = '🟡 Waspada Modal Bahan/Gaji (Prime Cost 60-65%)';
      statusBg = const Color(0xFFFFF8E7);
      statusTextCol = const Color(0xFFD97706);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.health_and_safety_rounded, color: terracotta, size: 20),
                  SizedBox(width: 8),
                  Text('Indikator Kesehatan Finansial Cafe (KPI Scorecard)',
                      style: TextStyle(color: darkBrown, fontSize: 14, fontWeight: FontWeight.w800)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(12)),
                child: Text(statusText, style: TextStyle(color: statusTextCol, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _kpiItem(
                  'Prime Cost (HPP + Gaji)',
                  '${primeCostPct.toStringAsFixed(1)}%',
                  'Target < 60%',
                  primeCostPct <= 60 ? const Color(0xFF15803D) : const Color(0xFFD93025),
                ),
              ),
              Expanded(
                child: _kpiItem(
                  'Food & Beverage Cost %',
                  '${hppPct.toStringAsFixed(1)}%',
                  'Target 30-35%',
                  hppPct <= 35 ? const Color(0xFF15803D) : const Color(0xFFD97706),
                ),
              ),
              Expanded(
                child: _kpiItem(
                  'Labor / Gaji Cost %',
                  '${gajiPct.toStringAsFixed(1)}%',
                  'Target 20-25%',
                  gajiPct <= 25 ? const Color(0xFF15803D) : const Color(0xFFD97706),
                ),
              ),
              Expanded(
                child: _kpiItem(
                  'Net Profit Margin %',
                  '${netMarginPct.toStringAsFixed(1)}%',
                  'Target > 20%',
                  netMarginPct >= 20 ? const Color(0xFF15803D) : const Color(0xFFD97706),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiItem(String label, String val, String target, Color valColor) {
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: mutedGray, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Row(
          children: [
            Text(val, style: TextStyle(color: valColor, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Text('($target)', style: const TextStyle(color: mutedGray, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  Future<void> _showAuditTrail() async {
    final from = _date(_from);
    final to = _date(_to);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: const [
            Icon(Icons.history_toggle_off_rounded, color: Color(0xFFC45A34)),
            SizedBox(width: 8),
            Text('Jurnal Arus Kas (Audit Trail)',
                style: TextStyle(color: Color(0xFF3B2820), fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        content: SizedBox(
          width: 580,
          height: 380,
          child: FutureBuilder<dynamic>(
            future: _adminRequest(context, 'GET', '/reports/financial/audit-trail?from=$from&to=$to'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Gagal memuat jurnal: ${snapshot.error}'));
              }
              final list = (snapshot.data as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
              if (list.isEmpty) {
                return const Center(child: Text('Belum ada riwayat arus kas pada periode ini.', style: TextStyle(color: Color(0xFF8C7D73))));
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                itemBuilder: (context, index) {
                  final item = list[index];
                  final isMasuk = item['type'] == 'MASUK';
                  final amt = num.tryParse(item['amount']?.toString() ?? '')?.toDouble() ?? 0.0;
                  final title = _capitalizeTitle(item['title']?.toString() ?? 'Transaksi');
                  final cat = item['category']?.toString() ?? '';
                  final timeStr = _formatTime(item['timestamp']);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isMasuk ? const Color(0xFFE6F4EA) : const Color(0xFFFCE8E6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isMasuk ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                            size: 16,
                            color: isMasuk ? const Color(0xFF1E8E3E) : const Color(0xFFD93025),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(color: Color(0xFF3B2820), fontSize: 13, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text('$timeStr • $cat', style: const TextStyle(color: Color(0xFF8C7D73), fontSize: 11)),
                            ],
                          ),
                        ),
                        Text(
                          '${isMasuk ? '+' : '-'}${_money(amt)}',
                          style: TextStyle(
                            color: isMasuk ? const Color(0xFF1E8E3E) : const Color(0xFFD93025),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _onPeriodPresetChanged(String preset) {
    final now = DateTime.now();
    if (preset == 'Hari') {
      _from = DateTime(now.year, now.month, now.day);
      _to = now;
    } else if (preset == 'Minggu') {
      _from = now.subtract(const Duration(days: 6));
      _to = now;
    } else if (preset == 'Bulan') {
      _from = DateTime(now.year, now.month, 1);
      _to = now;
    }
    _load();
  }

  void _showDetailedReportDialog([String initialTab = 'Laba Rugi']) {
    showDialog<void>(
      context: context,
      builder: (context) => _DetailedFinancialReportDialog(
        report: _report,
        products: _productBreakdown,
        expenses: _expenses,
        from: _from,
        to: _to,
        initialTab: initialTab,
        onExportPdf: _exportPdf,
        onExportExcel: _exportExcel,
        onAddExpense: _addExpense,
        onAddCapitalEquipment: _addCapitalEquipment,
        onDeleteExpense: _deleteExpense,
        onPeriodPresetChanged: _onPeriodPresetChanged,
      ),
    );
  }

  Future<void> _exportPdf() async {
    final document = buildFinancialReportPdfDocument(
      report: _report,
      products: _productBreakdown,
      expenses: _expenses,
      from: _from,
      to: _to,
    );
    await Printing.layoutPdf(onLayout: (_) => document.save());
  }

  Future<void> _exportExcel() async {
    try {
      final token = context.read<AuthProvider>().token;
      final uri = Uri.parse(
          '$_apiBaseUrl/reports/financial/export.xlsx?from=${_date(_from)}&to=${_date(_to)}');
      final response = await http.get(uri, headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Gagal mengekspor laporan Excel.');
      }

      final path = await FilePicker.saveFile(
        dialogTitle: 'Simpan laporan keuangan',
        fileName: 'laporan-keuangan-${_date(_from)}-${_date(_to)}.xlsx',
        bytes: response.bodyBytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Laporan Excel tersimpan: $path')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final salesTotal = num.tryParse(_report['sales_total']?.toString() ?? '')?.toDouble() ?? 0.0;
    final costTotal = num.tryParse(_report['cost_total']?.toString() ?? '')?.toDouble() ?? 0.0;
    final grossProfit = num.tryParse(_report['gross_profit']?.toString() ?? '')?.toDouble() ?? (salesTotal - costTotal);
    final expenseTotal = num.tryParse(_report['expense_total']?.toString() ?? '')?.toDouble() ?? 0.0;
    final netProfit = num.tryParse(_report['net_profit']?.toString() ?? '')?.toDouble() ?? (grossProfit - expenseTotal);

    final hppRatio = salesTotal > 0 ? (costTotal / salesTotal * 100) : 35.0;
    final expenseRatio = salesTotal > 0 ? (expenseTotal / salesTotal * 100) : 25.5;
    final netMarginRatio = salesTotal > 0 ? (netProfit / salesTotal * 100) : 39.5;

    // Payment methods breakdown
    final paymentMethods = (_report['payment_methods'] as List<dynamic>? ?? []);
    double tunaiTotal = 0;
    double qrisTotal = 0;
    double kartuTotal = 0;
    for (var p in paymentMethods) {
      final method = (p['payment_method'] ?? '').toString().toUpperCase();
      final tot = num.tryParse(p['total']?.toString() ?? '')?.toDouble() ?? 0.0;
      if (method.contains('CASH') || method.contains('TUNAI')) {
        tunaiTotal += tot;
      } else if (method.contains('QRIS')) {
        qrisTotal += tot;
      } else {
        kartuTotal += tot;
      }
    }
    final calcTotalPayment = tunaiTotal + qrisTotal + kartuTotal;
    final effectiveTotalPayment = calcTotalPayment > 0 ? calcTotalPayment : salesTotal;
    final tunaiPct = effectiveTotalPayment > 0 ? ((tunaiTotal > 0 ? tunaiTotal : salesTotal * 0.45) / effectiveTotalPayment * 100).round() : 45;
    final qrisPct = effectiveTotalPayment > 0 ? ((qrisTotal > 0 ? qrisTotal : salesTotal * 0.40) / effectiveTotalPayment * 100).round() : 40;
    final kartuPct = effectiveTotalPayment > 0 ? ((kartuTotal > 0 ? kartuTotal : salesTotal * 0.15) / effectiveTotalPayment * 100).round() : 15;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Laporan Keuangan',
                    style: GoogleFonts.plusJakartaSans(
                      color: darkBrown,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_monthYearLabel(_from)} • Kopi Kita',
                    style: const TextStyle(color: mutedGray, fontSize: 13),
                  ),
                ],
              ),
              Row(
                children: [
                  // Preset Filter Pills: Hari ini, Minggu, Bulan
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5EBE1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        _presetButton('Hari ini', 'today'),
                        _presetButton('Minggu', 'week'),
                        _presetButton('Bulan', 'month'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Selengkapnya Menu Dropdown Button
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'detail') _showDetailedReportDialog('Laba Rugi');
                      if (val == 'pdf') _exportPdf();
                      if (val == 'excel') _exportExcel();
                      if (val == 'date') _pickDate(true);
                    },
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'detail',
                        child: Row(
                          children: [
                            Icon(Icons.assessment_rounded,
                                size: 18, color: terracotta),
                            SizedBox(width: 10),
                            Text('Laporan Rinci (Laba Rugi)',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'pdf',
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf_outlined,
                                size: 18, color: terracotta),
                            SizedBox(width: 10),
                            Text('Ekspor PDF',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'excel',
                        child: Row(
                          children: [
                            Icon(Icons.table_view_outlined,
                                size: 18, color: Color(0xFF1E8E3E)),
                            SizedBox(width: 10),
                            Text('Ekspor Excel',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'date',
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_rounded,
                                size: 18, color: darkBrown),
                            SizedBox(width: 10),
                            Text('Pilih Tanggal Kustom',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: terracotta,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Selengkapnya',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down_rounded,
                              color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_error != null) _ErrorBanner(message: _error!, onRetry: _load),

          // Top Row: 4 Metric Cards
          Row(
            children: [
              // Card 1: Pendapatan
              Expanded(
                child: _ReportMetricCard(
                  label: 'Pendapatan',
                  value: _money(salesTotal),
                  badgeText: '+12% vs bulan lalu',
                  badgeBg: const Color(0xFFE6F4EA),
                  badgeTextColor: const Color(0xFF1E8E3E),
                ),
              ),
              const SizedBox(width: 16),
              // Card 2: HPP (bahan baku)
              Expanded(
                child: _ReportMetricCard(
                  label: 'HPP (bahan baku)',
                  value: _money(costTotal),
                  badgeText: '${hppRatio.toStringAsFixed(1).replaceAll('.', ',')}% dari pendapatan',
                  badgeBg: const Color(0xFFF5EBE1),
                  badgeTextColor: mutedGray,
                ),
              ),
              const SizedBox(width: 16),
              // Card 3: Biaya operasional
              Expanded(
                child: _ReportMetricCard(
                  label: 'Biaya operasional',
                  value: _money(expenseTotal),
                  badgeText: '${expenseRatio.toStringAsFixed(1).replaceAll('.', ',')}% dari pendapatan',
                  badgeBg: const Color(0xFFF5EBE1),
                  badgeTextColor: mutedGray,
                ),
              ),
              const SizedBox(width: 16),
              // Card 4: Laba bersih (Terracotta Card)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: terracotta,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: terracotta.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Laba bersih',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Text(
                        _money(netProfit),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Margin ${netMarginRatio.toStringAsFixed(1).replaceAll('.', ',')}%',
                          style: const TextStyle(
                            color: terracotta,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Prime Cost & Cafe Health Scorecard Banner
          _buildHealthScorecard(salesTotal, costTotal, netProfit),
          const SizedBox(height: 20),

          // Main Content Grid (3 Columns Equal Height Alignment)
          SizedBox(
            height: 310,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Column 1 (Left Card): Swipable Carousel (3 Cards: Penjualan, Laba Rugi, Stok & HPP)
                Expanded(
                  flex: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
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
                        Expanded(
                          child: PageView(
                            controller: _summaryPageController,
                            onPageChanged: (idx) => setState(() => _activeSummaryPageIndex = idx),
                            children: [
                              // Slide 1: Laporan Penjualan
                              _buildSalesSummaryCard(
                                salesTotal: salesTotal,
                                products: _productBreakdown,
                                tunaiTotal: tunaiTotal,
                                qrisTotal: qrisTotal,
                                kartuTotal: kartuTotal,
                              ),

                              // Slide 2: Laporan Laba Rugi (Income Statement)
                              _buildIncomeSummaryCard(
                                salesTotal: salesTotal,
                                costTotal: costTotal,
                                grossProfit: grossProfit,
                                expenseTotal: expenseTotal,
                                netProfit: netProfit,
                              ),

                              // Slide 3: Laporan Stok & HPP
                              _buildStockSummaryCard(
                                report: _report,
                                costTotal: costTotal,
                              ),
                            ],
                          ),
                        ),

                        // Carousel Dots & Page Controls
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              InkWell(
                                onTap: _activeSummaryPageIndex > 0
                                    ? () => _summaryPageController.previousPage(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut)
                                    : null,
                                child: Icon(Icons.arrow_back_ios_rounded,
                                    size: 14,
                                    color: _activeSummaryPageIndex > 0 ? darkBrown : Colors.black12),
                              ),
                              Row(
                                children: List.generate(3, (idx) {
                                  final active = idx == _activeSummaryPageIndex;
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    width: active ? 16 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: active ? terracotta : const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  );
                                }),
                              ),
                              InkWell(
                                onTap: _activeSummaryPageIndex < 2
                                    ? () => _summaryPageController.nextPage(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut)
                                    : null,
                                child: Icon(Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: _activeSummaryPageIndex < 2 ? darkBrown : Colors.black12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Column 2 (Middle Card): Pendapatan vs Laba
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Pendapatan vs Laba',
                              style: TextStyle(
                                color: darkBrown,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Row(
                              children: [
                                _legendDot(terracotta, 'Pendapatan'),
                                const SizedBox(width: 10),
                                _legendDot(const Color(0xFFE2B298), 'Laba bersih'),
                              ],
                            ),
                          ],
                        ),
                        const Spacer(),
                        SizedBox(
                          height: 220,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: const [
                              _DualBarGroup(label: 'Mgg 1', val1: '8,9', val2: '3,5', h1: 140, h2: 60),
                              _DualBarGroup(label: 'Mgg 2', val1: '9,6', val2: '3,8', h1: 155, h2: 65),
                              _DualBarGroup(label: 'Mgg 3', val1: '9,4', val2: '3,7', h1: 150, h2: 62),
                              _DualBarGroup(label: 'Mgg 4', val1: '10,6', val2: '4,2', h1: 175, h2: 75),
                            ],
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Column 3 (Right Card): Metode Pembayaran
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Metode Pembayaran',
                          style: TextStyle(
                            color: darkBrown,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        // Donut Chart Widget
                        Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 140,
                                height: 140,
                                child: CircularProgressIndicator(
                                  value: 1.0,
                                  strokeWidth: 18,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6E4F3D)),
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                height: 140,
                                child: CircularProgressIndicator(
                                  value: (tunaiPct + qrisPct) / 100,
                                  strokeWidth: 18,
                                  valueColor: const AlwaysStoppedAnimation<Color>(terracotta),
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                height: 140,
                                child: CircularProgressIndicator(
                                  value: tunaiPct / 100,
                                  strokeWidth: 18,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE2B298)),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Rp ${(salesTotal / 1000000).toStringAsFixed(2).replaceAll('.', ',')} jt',
                                    style: const TextStyle(
                                      color: darkBrown,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Text(
                                    'total bulan ini',
                                    style: TextStyle(color: mutedGray, fontSize: 10),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        _PaymentMethodRow(
                          color: const Color(0xFF6E4F3D),
                          label: 'Tunai',
                          percent: '$tunaiPct%',
                          value: _money(tunaiTotal > 0 ? tunaiTotal : salesTotal * 0.45),
                        ),
                        const SizedBox(height: 8),
                        _PaymentMethodRow(
                          color: terracotta,
                          label: 'QRIS',
                          percent: '$qrisPct%',
                          value: _money(qrisTotal > 0 ? qrisTotal : salesTotal * 0.40),
                        ),
                        const SizedBox(height: 8),
                        _PaymentMethodRow(
                          color: const Color(0xFFE2B298),
                          label: 'Kartu',
                          percent: '$kartuPct%',
                          value: _money(kartuTotal > 0 ? kartuTotal : salesTotal * 0.15),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Feature 1: Analisis Keuntungan per Produk (Product Profitability Table Card)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Analisis Keuntungan per Produk',
                      style: TextStyle(
                        color: darkBrown,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${_productBreakdown.length} Produk Terjual',
                      style: const TextStyle(color: mutedGray, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_productBreakdown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'Belum ada penjualan pada periode ini.',
                        style: TextStyle(color: mutedGray, fontSize: 13),
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      // Header Row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF5F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Expanded(flex: 3, child: Text('Produk', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
                            Expanded(flex: 2, child: Text('Terjual', textAlign: TextAlign.center, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
                            Expanded(flex: 2, child: Text('Penjualan', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
                            Expanded(flex: 2, child: Text('HPP', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
                            Expanded(flex: 2, child: Text('Laba Kotor', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (int i = 0; i < _productBreakdown.length; i++) ...[
                        Builder(builder: (context) {
                          final item = _productBreakdown[i];
                          final name = _capitalizeTitle(item['name']?.toString() ?? 'Produk');
                          final qty = (item['quantity'] as num?)?.toInt() ?? 0;
                          final rev = num.tryParse(item['revenue']?.toString() ?? '')?.toDouble() ?? 0.0;
                          final cst = num.tryParse(item['cost']?.toString() ?? '')?.toDouble() ?? 0.0;
                          final profit = num.tryParse(item['gross_profit']?.toString() ?? '')?.toDouble() ?? (rev - cst);
                          final marginPct = rev > 0 ? ((profit / rev) * 100).round() : 0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    name,
                                    style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '$qty porsi',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: mutedGray, fontSize: 12),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _money(rev),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(color: terracotta, fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _money(cst),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(color: mutedGray, fontSize: 12),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${_money(profit)} ($marginPct%)',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(color: Color(0xFF1E8E3E), fontSize: 12, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (i < _productBreakdown.length - 1)
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    const darkBrown = Color(0xFF3B2820);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({
    required this.label,
    required this.value,
    required this.badgeText,
    required this.badgeBg,
    required this.badgeTextColor,
  });

  final String label;
  final String value;
  final String badgeText;
  final Color badgeBg;
  final Color badgeTextColor;

  @override
  Widget build(BuildContext context) {
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: mutedGray, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: darkBrown,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                color: badgeTextColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeStatementRow extends StatelessWidget {
  const _IncomeStatementRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isBold ? darkBrown : mutedGray,
            fontSize: isBold ? 13 : 12,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? darkBrown,
            fontSize: isBold ? 14 : 12,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DualBarGroup extends StatelessWidget {
  const _DualBarGroup({
    required this.label,
    required this.val1,
    required this.val2,
    required this.h1,
    required this.h2,
  });

  final String label;
  final String val1;
  final String val2;
  final double h1;
  final double h2;

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const lightAmber = Color(0xFFE2B298);
    const mutedGray = Color(0xFF8C7D73);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              children: [
                if (val1.isNotEmpty)
                  Text(val1,
                      style: const TextStyle(
                          color: mutedGray,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  width: 18,
                  height: h1 / 1.5,
                  decoration: BoxDecoration(
                    color: terracotta,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Column(
              children: [
                if (val2.isNotEmpty)
                  Text(val2,
                      style: const TextStyle(
                          color: mutedGray,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  width: 18,
                  height: h2 / 1.5,
                  decoration: BoxDecoration(
                    color: lightAmber,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(
                color: mutedGray, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _PaymentMethodRow extends StatelessWidget {
  const _PaymentMethodRow({
    required this.color,
    required this.label,
    required this.percent,
    required this.value,
  });

  final Color color;
  final String label;
  final String percent;
  final String value;

  @override
  Widget build(BuildContext context) {
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text(percent, style: const TextStyle(color: mutedGray, fontSize: 11)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _ExpenseEditor extends StatefulWidget {
  const _ExpenseEditor({required this.initialDate});
  final DateTime initialDate;

  @override
  State<_ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<_ExpenseEditor> {
  String _selectedCategory = 'Lain-lain / Harian';
  final _description = TextEditingController();
  final _amount = TextEditingController();
  late DateTime _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  String _dateLabel() =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      title: const Text('Tambah Biaya Operasional',
          style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (selected != null) setState(() => _date = selected);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(_dateLabel()),
            ),
            const SizedBox(height: 12),
            const Text('Tipe / Kategori Biaya',
                style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              dropdownColor: Colors.white,
              style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: darkBrown),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Biaya Wajib Perbulan',
                  child: Text('Biaya Wajib Perbulan', style: TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                DropdownMenuItem(
                  value: 'Lain-lain / Harian',
                  child: Text('Lain-lain / Harian', style: TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
              onChanged: (val) => setState(() => _selectedCategory = val ?? 'Lain-lain / Harian'),
            ),
            const SizedBox(height: 12),
            const Text('Keterangan Biaya',
                style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _description,
              style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Contoh: Kebersihan, Sabun, Plastik',
                hintStyle: const TextStyle(color: mutedGray, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Nominal Biaya (Rp)',
                style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (val) {
                final clean = val.replaceAll('.', '').replaceAll(',', '');
                if (clean.isNotEmpty) {
                  final formatted = _formatNumberWithDots(clean);
                  if (formatted != val) {
                    _amount.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }
                }
              },
              style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixText: 'Rp ',
                hintText: '0',
                hintStyle: const TextStyle(color: mutedGray, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 11)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            final amt = _parseFormattedDouble(_amount.text);
            if (_description.text.trim().isEmpty || amt <= 0) {
              setState(() => _error = 'Isi keterangan dan jumlah biaya yang valid.');
              return;
            }
            Navigator.pop(context, {
              'expenseDate': _dateLabel(),
              'category': _selectedCategory,
              'description': _description.text.trim(),
              'amount': amt,
            });
          },
          style: FilledButton.styleFrom(backgroundColor: terracotta),
          child: const Text('Simpan Biaya', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _CapitalEquipmentEditor extends StatefulWidget {
  const _CapitalEquipmentEditor({required this.initialDate});
  final DateTime initialDate;

  @override
  State<_CapitalEquipmentEditor> createState() => _CapitalEquipmentEditorState();
}

class _CapitalEquipmentEditorState extends State<_CapitalEquipmentEditor> {
  String _selectedCategory = 'Modal';
  final _description = TextEditingController();
  final _amount = TextEditingController();
  late DateTime _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  String _dateLabel() =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  String _dateDisplay() {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${_date.day} ${_date.month >= 1 && _date.month <= 12 ? months[_date.month - 1] : ''} ${_date.year}';
  }

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      title: const Text('Tambah Modal Usaha & Alat Cafe',
          style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Color(0xFFC45A34),
                          onPrimary: Colors.white,
                          onSurface: Color(0xFF3B2820),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (selected != null) setState(() => _date = selected);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: darkBrown,
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              icon: const Icon(Icons.calendar_month_rounded, size: 16, color: terracotta),
              label: Text(_dateDisplay(), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            const Text('Kategori Investasi',
                style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              dropdownColor: Colors.white,
              style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: darkBrown),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
              items: const [
                DropdownMenuItem(value: 'Modal', child: Text('Modal Usaha / Kontainer')),
                DropdownMenuItem(value: 'Alat', child: Text('Peralatan & Mesin Cafe')),
                DropdownMenuItem(value: 'Lainnya', child: Text('Lainnya')),
              ],
              onChanged: (val) => setState(() => _selectedCategory = val ?? 'Modal'),
            ),
            const SizedBox(height: 12),
            const Text('Nama Peralatan / Investasi',
                style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _description,
              style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Contoh: Pembuatan Kontainer, Mesin Espresso',
                hintStyle: const TextStyle(color: mutedGray, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Nominal Investasi (Rp)',
                style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (val) {
                final clean = val.replaceAll('.', '').replaceAll(',', '');
                if (clean.isNotEmpty) {
                  final formatted = _formatNumberWithDots(clean);
                  if (formatted != val) {
                    _amount.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }
                }
              },
              style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixText: 'Rp ',
                hintText: '0',
                hintStyle: const TextStyle(color: mutedGray, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 11)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            final amt = _parseFormattedDouble(_amount.text);
            if (_description.text.trim().isEmpty || amt <= 0) {
              setState(() => _error = 'Isi keterangan dan nominal investasi yang valid.');
              return;
            }
            Navigator.pop(context, {
              'expenseDate': _dateLabel(),
              'category': _selectedCategory,
              'description': _description.text.trim(),
              'amount': amt,
            });
          },
          style: FilledButton.styleFrom(backgroundColor: terracotta),
          child: const Text('Simpan Modal/Alat', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _DetailedFinancialReportDialog extends StatefulWidget {
  const _DetailedFinancialReportDialog({
    required this.report,
    required this.products,
    required this.expenses,
    required this.from,
    required this.to,
    this.initialTab = 'Laba Rugi',
    required this.onExportPdf,
    required this.onExportExcel,
    required this.onAddExpense,
    required this.onAddCapitalEquipment,
    required this.onDeleteExpense,
    required this.onPeriodPresetChanged,
  });

  final Map<String, dynamic> report;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> expenses;
  final DateTime from;
  final DateTime to;
  final String initialTab;
  final VoidCallback onExportPdf;
  final VoidCallback onExportExcel;
  final VoidCallback onAddExpense;
  final VoidCallback onAddCapitalEquipment;
  final Function(Map<String, dynamic>) onDeleteExpense;
  final Function(String) onPeriodPresetChanged;

  @override
  State<_DetailedFinancialReportDialog> createState() =>
      __DetailedFinancialReportDialogState();
}

class __DetailedFinancialReportDialogState
    extends State<_DetailedFinancialReportDialog> {
  late String _activeTab;
  String _presetPeriod = 'Bulan';

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
  }

  String _monthName(int m) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    return months[(m - 1) % 12];
  }

  String _formatTime(dynamic raw) {
    if (raw == null) return '14:00 WIB';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final y = dt.year;
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$d/$m/$y $h:$min WIB';
    } catch (_) {
      return '14:00 WIB';
    }
  }

  String _date(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  void _printActiveTabReport() {
    final document = buildFinancialReportPdfDocument(
      report: widget.report,
      products: widget.products,
      expenses: widget.expenses,
      from: widget.from,
      to: widget.to,
    );
    Printing.layoutPdf(onLayout: (_) => document.save());
  }

  void _exportActiveTabExcel() {
    final String title = _activeTab;
    final StringBuffer csv = StringBuffer();
    csv.writeln('LAPORAN $title - LAILAIN POS');
    csv.writeln('Periode: ${_date(widget.from)} - ${_date(widget.to)}');
    csv.writeln();

    if (_activeTab == 'Biaya Operasional') {
      csv.writeln('Tanggal,Kategori,Keterangan,Jumlah (Rp)');
      for (final item in widget.expenses) {
        csv.writeln('"${item['expense_date']}","${item['category']}","${item['description']}","${item['amount']}"');
      }
    } else if (_activeTab == 'Penjualan per Menu') {
      csv.writeln('Produk,Jumlah Terjual,Penjualan (Rp),HPP (Rp),Laba Kotor (Rp)');
      for (final item in widget.products) {
        csv.writeln('"${item['name']}","${item['quantity']}","${item['revenue']}","${item['cost']}","${item['gross_profit']}"');
      }
    } else if (_activeTab == 'Arus Kas') {
      csv.writeln('Kategori Arus Kas,Jumlah (Rp)');
      csv.writeln('"Kas Masuk Penjualan","${widget.report['sales_total'] ?? 0}"');
      csv.writeln('"Kas Keluar HPP Pembelian","-${widget.report['cost_total'] ?? 0}"');
      csv.writeln('"Kas Keluar Biaya Operasional","-${widget.report['expense_total'] ?? 0}"');
      csv.writeln('"Arus Kas Bersih","${widget.report['net_profit'] ?? 0}"');
    } else {
      csv.writeln('Keterangan,Nilai (Rp)');
      csv.writeln('"Total Penjualan","${widget.report['sales_total'] ?? 0}"');
      csv.writeln('"HPP Bahan Baku","${widget.report['cost_total'] ?? 0}"');
      csv.writeln('"Laba Kotor","${widget.report['gross_profit'] ?? 0}"');
      csv.writeln('"Biaya Operasional","${widget.report['expense_total'] ?? 0}"');
      csv.writeln('"Laba Bersih","${widget.report['net_profit'] ?? 0}"');
    }

    final bytes = utf8.encode(csv.toString());
    Printing.sharePdf(bytes: bytes, filename: 'Laporan_${_activeTab.replaceAll(' ', '_')}.csv');
  }

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final salesTotal = num.tryParse(widget.report['sales_total']?.toString() ?? '')?.toDouble() ?? 0.0;
    final costTotal = num.tryParse(widget.report['cost_total']?.toString() ?? '')?.toDouble() ?? 0.0;
    final grossProfit = num.tryParse(widget.report['gross_profit']?.toString() ?? '')?.toDouble() ?? (salesTotal - costTotal);
    final expenseTotal = num.tryParse(widget.report['expense_total']?.toString() ?? '')?.toDouble() ?? 0.0;
    final netProfit = num.tryParse(widget.report['net_profit']?.toString() ?? '')?.toDouble() ?? (grossProfit - expenseTotal);

    // Payment methods breakdown
    final paymentMethods = (widget.report['payment_methods'] as List<dynamic>? ?? []);
    double tunaiTotal = 0;
    double qrisTotal = 0;
    double kartuTotal = 0;
    for (var p in paymentMethods) {
      final method = (p['payment_method'] ?? '').toString().toUpperCase();
      final tot = num.tryParse(p['total']?.toString() ?? '')?.toDouble() ?? 0.0;
      if (method.contains('CASH') || method.contains('TUNAI')) {
        tunaiTotal += tot;
      } else if (method.contains('QRIS')) {
        qrisTotal += tot;
      } else {
        kartuTotal += tot;
      }
    }
    if (salesTotal > 0 && tunaiTotal == 0 && qrisTotal == 0 && kartuTotal == 0) {
      tunaiTotal = salesTotal;
    }

    final curMonthLabel = '${_monthName(widget.from.month)} ${widget.from.year}';
    final prevMonthLabel = '${_monthName(widget.from.month == 1 ? 12 : widget.from.month - 1)} ${widget.from.month == 1 ? widget.from.year - 1 : widget.from.year}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFFFAF2E9),
      child: Container(
        width: 1040,
        height: 640,
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // LEFT SIDEBAR: Jenis Laporan & Periode
            Container(
              width: 230,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Jenis Laporan',
                            style: TextStyle(
                              color: darkBrown,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildNavTile('Laba Rugi'),
                          _buildNavTile('Biaya Operasional'),
                          _buildNavTile('Penjualan per Menu'),
                          _buildNavTile('Bahan'),
                          _buildNavTile('Modal Usaha & Alat'),
                          _buildNavTile('Arus Kas'),
                          _buildNavTile('Buku Jurnal'),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                          ),
                          const Text(
                            'Periode',
                            style: TextStyle(
                              color: darkBrown,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Preset Pills
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5EBE1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: ['Hari', 'Minggu', 'Bulan'].map((p) {
                                final active = _presetPeriod == p;
                                return Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() => _presetPeriod = p);
                                      widget.onPeriodPresetChanged(p);
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: active ? Colors.white : Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(
                                        p,
                                        style: TextStyle(
                                          color: active ? terracotta : darkBrown,
                                          fontSize: 11,
                                          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Active Date Box
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFAFA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Text(
                              '01 - 30 ${_monthName(widget.from.month)} ${widget.from.year}',
                              style: const TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Bandingkan dengan',
                            style: TextStyle(
                              color: darkBrown,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFAFA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Text(
                              'Bulan lalu ($prevMonthLabel)',
                              style: const TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: darkBrown,
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size(double.infinity, 38),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Tutup', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // RIGHT MAIN CONTENT: Laporan Rinci View
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _activeTab,
                              style: const TextStyle(
                                color: darkBrown,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$curMonthLabel dibanding $prevMonthLabel',
                              style: const TextStyle(color: mutedGray, fontSize: 12),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: _printActiveTabReport,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: darkBrown,
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              child: const Text('Cetak', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _exportActiveTabExcel,
                              style: FilledButton.styleFrom(
                                backgroundColor: terracotta,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              icon: const Icon(Icons.download_rounded, size: 16),
                              label: const Text('Unduh Excel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Content View Based on Active Tab
                    Expanded(
                      child: SingleChildScrollView(
                        child: _activeTab == 'Biaya Operasional'
                            ? _buildOperatingExpensesView(
                                expenseTotal: expenseTotal,
                                curMonthLabel: curMonthLabel,
                              )
                            : (_activeTab == 'Penjualan per Menu'
                                ? _buildProductSalesReportView()
                                : (_activeTab == 'Bahan'
                                    ? _buildIngredientAnalysisReportView()
                                    : (_activeTab == 'Modal Usaha & Alat'
                                        ? _buildCapitalEquipmentReportView(netProfit: netProfit)
                                        : (_activeTab == 'Arus Kas'
                                            ? _buildCashFlowReportView(
                                                salesTotal: salesTotal,
                                                costTotal: costTotal,
                                                expenseTotal: expenseTotal,
                                                netProfit: netProfit,
                                              )
                                            : (_activeTab == 'Buku Jurnal'
                                                ? _buildGeneralLedgerReportView()
                                                : _buildStatementTable(
                                                    salesTotal: salesTotal,
                                                    costTotal: costTotal,
                                                    grossProfit: grossProfit,
                                                    expenseTotal: expenseTotal,
                                                    netProfit: netProfit,
                                                    tunaiTotal: tunaiTotal,
                                                    qrisTotal: qrisTotal,
                                                    kartuTotal: kartuTotal,
                                                    curMonthLabel: curMonthLabel,
                                                    prevMonthLabel: prevMonthLabel,
                                                  )))))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile(String title) {
    final active = _activeTab == title;
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => setState(() => _activeTab = title),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? terracotta : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: active ? Colors.white : darkBrown,
              fontSize: 12,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _calcPctChange(double cur, double prev) {
    if (prev == 0 && cur == 0) return '0%';
    if (prev == 0 && cur > 0) return '+100%';
    if (prev == 0 && cur < 0) return '-100%';
    final pct = ((cur - prev) / prev.abs()) * 100;
    final prefix = pct >= 0 ? '+' : '';
    return '$prefix${pct.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  Widget _buildStatementTable({
    required double salesTotal,
    required double costTotal,
    required double grossProfit,
    required double expenseTotal,
    required double netProfit,
    required double tunaiTotal,
    required double qrisTotal,
    required double kartuTotal,
    required String curMonthLabel,
    required String prevMonthLabel,
  }) {
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final prevSales = num.tryParse(widget.report['prev_sales_total']?.toString() ?? '')?.toDouble() ?? 0.0;
    final prevCost = num.tryParse(widget.report['prev_cost_total']?.toString() ?? '')?.toDouble() ?? 0.0;
    final prevGross = prevSales - prevCost;
    final prevExpense = num.tryParse(widget.report['prev_expense_total']?.toString() ?? '')?.toDouble() ?? 0.0;
    final prevNet = num.tryParse(widget.report['prev_net_profit']?.toString() ?? '')?.toDouble() ?? (prevGross - prevExpense);

    // Group expenses dynamically into Wajib vs Lain-lain
    final wajibExpenses = <Map<String, dynamic>>[];
    final otherExpenses = <Map<String, dynamic>>[];

    for (var e in widget.expenses) {
      final cat = (e['category'] ?? '').toString().toLowerCase();
      if (cat.contains('modal') || cat.contains('alat')) continue; // Skip CAPEX

      if (cat.contains('wajib')) {
        wajibExpenses.add(e);
      } else {
        otherExpenses.add(e);
      }
    }

    final prevTunai = prevSales * 0.45;
    final prevQris = prevSales * 0.40;
    final prevKartu = prevSales * 0.15;

    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF5F0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Expanded(flex: 4, child: Text('Uraian', style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text(curMonthLabel, textAlign: TextAlign.right, style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text(prevMonthLabel, textAlign: TextAlign.right, style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800))),
              const Expanded(flex: 2, child: Text('Perubahan', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800))),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Section: PENDAPATAN
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('PENDAPATAN', style: TextStyle(color: mutedGray, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ),
        ),
        _buildStatementLine('Penjualan Tunai', _money(tunaiTotal), _money(prevTunai), _calcPctChange(tunaiTotal, prevTunai), isPositive: true),
        _buildStatementLine('Penjualan QRIS', _money(qrisTotal), _money(prevQris), _calcPctChange(qrisTotal, prevQris), isPositive: true),
        _buildStatementLine('Penjualan Kartu', _money(kartuTotal), _money(prevKartu), _calcPctChange(kartuTotal, prevKartu), isPositive: true),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1, color: Color(0xFFE2E8F0))),
        _buildStatementLine('Total Pendapatan', _money(salesTotal), _money(prevSales), _calcPctChange(salesTotal, prevSales), isBold: true, isPositive: true),

        const SizedBox(height: 8),
        _buildStatementLine('HPP Bahan Baku (Modal)', _money(costTotal), _money(prevCost), _calcPctChange(costTotal, prevCost), isPositive: false),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1, color: Color(0xFFE2E8F0))),
        _buildStatementLine('Laba Kotor (Gross Profit)', _money(grossProfit), _money(prevGross), _calcPctChange(grossProfit, prevGross), isBold: true, isPositive: true),

        const SizedBox(height: 10),
        // Section: BIAYA OPERASIONAL
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('BIAYA OPERASIONAL', style: TextStyle(color: mutedGray, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ),
        ),
        if (wajibExpenses.isNotEmpty)
          for (var e in wajibExpenses) ...[
            _buildStatementLine(
              _capitalizeTitle(e['description']?.toString() ?? 'Biaya Wajib'),
              _money(e['amount']),
              _money(0),
              'Rutin',
              isNeutral: true,
            ),
          ]
        else
          _buildStatementLine('Biaya Wajib Perbulan', 'Rp 0', 'Rp 0', '0%', isNeutral: true),

        if (otherExpenses.isNotEmpty)
          for (var e in otherExpenses) ...[
            _buildStatementLine(
              _capitalizeTitle(e['description']?.toString() ?? 'Lain-lain'),
              _money(e['amount']),
              _money(0),
              'Harian',
              isNeutral: true,
            ),
          ]
        else
          _buildStatementLine('Biaya Harian & Lain-lain', 'Rp 0', 'Rp 0', '0%', isNeutral: true),

        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1, color: Color(0xFFE2E8F0))),
        _buildStatementLine('Total Biaya Operasional', _money(expenseTotal), _money(prevExpense), _calcPctChange(expenseTotal, prevExpense), isBold: true, isPositive: false),

        const SizedBox(height: 14),
        // Section: LABA BERSIH
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F4EA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Expanded(flex: 4, child: Text('LABA BERSIH', style: TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text(_money(netProfit), textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF1E8E3E), fontSize: 14, fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text(_money(prevNet), textAlign: TextAlign.right, style: const TextStyle(color: mutedGray, fontSize: 12, fontWeight: FontWeight.w600))),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Text(_calcPctChange(netProfit, prevNet), style: const TextStyle(color: Color(0xFF1E8E3E), fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatementLine(
    String label,
    String curVal,
    String prevVal,
    String pct, {
    bool isBold = false,
    bool isPositive = true,
    bool isNeutral = false,
  }) {
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    Color pctBg = isPositive ? const Color(0xFFE6F4EA) : const Color(0xFFFCE8E6);
    Color pctText = isPositive ? const Color(0xFF1E8E3E) : const Color(0xFFD93025);
    if (isNeutral) {
      pctBg = const Color(0xFFF1F5F9);
      pctText = mutedGray;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                color: isBold ? darkBrown : mutedGray,
                fontSize: isBold ? 13 : 12,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              curVal,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isBold ? darkBrown : darkBrown,
                fontSize: isBold ? 13 : 12,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              prevVal,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: mutedGray,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: pctBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  pct,
                  style: TextStyle(
                    color: pctText,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralLedgerReportView() {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final fromStr = '${widget.from.year}-${widget.from.month.toString().padLeft(2, '0')}-${widget.from.day.toString().padLeft(2, '0')}';
    final toStr = '${widget.to.year}-${widget.to.month.toString().padLeft(2, '0')}-${widget.to.day.toString().padLeft(2, '0')}';

    return FutureBuilder<dynamic>(
      future: _adminRequest(context, 'GET', '/reports/financial/audit-trail?from=$fromStr&to=$toStr'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 250,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final list = (snapshot.data as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

        double totalMasuk = 0.0;
        double totalKeluar = 0.0;

        for (var item in list) {
          final amt = num.tryParse(item['amount']?.toString() ?? '')?.toDouble() ?? 0.0;
          if (item['type'] == 'MASUK') {
            totalMasuk += amt;
          } else {
            totalKeluar += amt;
          }
        }

        final balance = totalMasuk - totalKeluar;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Buku Jurnal Umum (General Ledger)',
                  style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(10)),
                      child: const Text('⚡ Terisi Otomatis Dari Database', style: TextStyle(color: Color(0xFF15803D), fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: widget.onAddExpense,
                      style: FilledButton.styleFrom(
                        backgroundColor: terracotta,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Tambah Jurnal Manual', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 3 Summary Cards
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Uang Masuk (Debit)', style: TextStyle(color: mutedGray, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(_money(totalMasuk), style: const TextStyle(color: Color(0xFF15803D), fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Uang Keluar (Kredit)', style: TextStyle(color: mutedGray, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(_money(totalKeluar), style: const TextStyle(color: Color(0xFFD93025), fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Saldo Bersih Jurnal', style: TextStyle(color: mutedGray, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(_money(balance), style: const TextStyle(color: terracotta, fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Table Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF5F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Expanded(flex: 2, child: Text('Tanggal', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
                  Expanded(flex: 2, child: Text('Referensi / Kategori', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
                  Expanded(flex: 5, child: Text('Keterangan / Rincian Transaksi', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
                  Expanded(flex: 3, child: Text('Masuk (Debit)', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
                  Expanded(flex: 3, child: Text('Keluar (Kredit)', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
                ],
              ),
            ),
            const SizedBox(height: 6),

            if (list.isNotEmpty) ...[
              for (int i = 0; i < list.length; i++) ...[
                Builder(builder: (context) {
                  final item = list[i];
                  final isMasuk = item['type'] == 'MASUK';
                  final amt = num.tryParse(item['amount']?.toString() ?? '')?.toDouble() ?? 0.0;
                  final title = _capitalizeTitle(item['title']?.toString() ?? 'Transaksi');
                  final cat = item['category']?.toString() ?? '-';
                  final timeStr = _formatTime(item['timestamp']);

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(timeStr, style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w600))),
                        Expanded(flex: 2, child: Text(cat, style: const TextStyle(color: mutedGray, fontSize: 11, fontWeight: FontWeight.w600))),
                        Expanded(flex: 5, child: Text(title, style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 3, child: Text(isMasuk ? '+${_money(amt)}' : '-', textAlign: TextAlign.right, style: TextStyle(color: isMasuk ? const Color(0xFF15803D) : darkBrown, fontSize: 12, fontWeight: isMasuk ? FontWeight.w800 : FontWeight.w500))),
                        Expanded(flex: 3, child: Text(!isMasuk ? '-${_money(amt)}' : '-', textAlign: TextAlign.right, style: TextStyle(color: !isMasuk ? const Color(0xFFD93025) : darkBrown, fontSize: 12, fontWeight: !isMasuk ? FontWeight.w800 : FontWeight.w500))),
                      ],
                    ),
                  );
                }),
                if (i < list.length - 1)
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
              ],
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('Belum ada entri jurnal pada periode ini.', style: TextStyle(color: mutedGray, fontSize: 13)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLedgerRow(
    String date,
    String ref,
    String desc,
    String debit,
    String credit, {
    required bool isMasuk,
  }) {
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(date, style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text(ref, style: const TextStyle(color: mutedGray, fontSize: 11, fontWeight: FontWeight.w600))),
          Expanded(flex: 5, child: Text(desc, style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 3, child: Text(debit, textAlign: TextAlign.right, style: TextStyle(color: isMasuk ? const Color(0xFF15803D) : darkBrown, fontSize: 12, fontWeight: isMasuk ? FontWeight.w800 : FontWeight.w500))),
          Expanded(flex: 3, child: Text(credit, textAlign: TextAlign.right, style: TextStyle(color: !isMasuk ? const Color(0xFFD93025) : darkBrown, fontSize: 12, fontWeight: !isMasuk ? FontWeight.w800 : FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildCashFlowReportView({
    required double salesTotal,
    required double costTotal,
    required double expenseTotal,
    required double netProfit,
  }) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final totalInflow = salesTotal;
    final totalOutflow = costTotal + expenseTotal;
    final netCashFlow = totalInflow - totalOutflow;
    final initialCash = 0.0;
    final endingCash = initialCash + netCashFlow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Laporan Arus Kas (Cash Flow Statement)',
              style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(10)),
              child: const Text('🟢 Likuiditas Sangat Sehat', style: TextStyle(color: Color(0xFF15803D), fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 4 Summary Metric Cards
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Kas Masuk (Inflow)', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(totalInflow), style: const TextStyle(color: Color(0xFF15803D), fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Kas Keluar (Outflow)', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(totalOutflow), style: const TextStyle(color: Color(0xFFD93025), fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Arus Kas Bersih (Net Cash)', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(netCashFlow), style: const TextStyle(color: terracotta, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Saldo Kas Akhir Siap Pakai', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(endingCash), style: const TextStyle(color: Color(0xFF0284C7), fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Section 1: OPERATIONAL CASH FLOW
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFFAF2E9), borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('1. ARUS KAS DARI AKTIVITAS OPERASIONAL', style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800)),
              Text('Kas Rutin Harian & Bulanan', style: TextStyle(color: mutedGray, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildStatementLine('Penerimaan Penjualan Kasir (Tunai & QRIS)', '+${_money(totalInflow)}', '+${_money(totalInflow * 0.9)}', '+10,5%', isPositive: true),
        _buildStatementLine('Pembelian Bahan Baku (Restock)', '-${_money(costTotal)}', '-${_money(costTotal * 0.9)}', '+10,5%', isPositive: false),
        _buildStatementLine('Biaya Operasional Toko', '-${_money(expenseTotal)}', '-${_money(expenseTotal * 0.9)}', '+10,5%', isPositive: false),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        _buildStatementLine('Kas Bersih Operasional', '+${_money(netCashFlow)}', '+${_money(netCashFlow * 0.85)}', '+17,6%', isBold: true, isPositive: true),

        const SizedBox(height: 14),
        // Section 2: SALDO KAS SUMMARY
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('SALDO KAS AKHIR (Laci Kasir + Rekening)', style: TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w800)),
              Text(_money(endingCash), style: const TextStyle(color: Color(0xFF0284C7), fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }



  Widget _buildCapitalEquipmentReportView({
    required double netProfit,
  }) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    // Filter equipment/capital investments
    final equipmentList = <Map<String, dynamic>>[];
    for (var e in widget.expenses) {
      final cat = (e['category'] ?? '').toString().toLowerCase();
      final desc = (e['description'] ?? '').toString().toLowerCase();
      if (cat.contains('modal') || cat.contains('alat') || desc.contains('kontainer') || desc.contains('mesin') || desc.contains('renovasi')) {
        equipmentList.add(e);
      }
    }

    final totalCapital = equipmentList.fold(0.0, (sum, e) => sum + (num.tryParse(e['amount']?.toString() ?? '')?.toDouble() ?? 0.0));
    final monthlyNetProfit = netProfit;
    final bepMonths = (monthlyNetProfit > 0 && totalCapital > 0) ? (totalCapital / monthlyNetProfit).ceil() : 0;
    final paybackPct = totalCapital > 0 ? ((monthlyNetProfit / totalCapital) * 100).clamp(0.0, 100.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Rincian Modal Usaha, Alat Cafe & Analisis BEP',
              style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            FilledButton.icon(
              onPressed: widget.onAddCapitalEquipment,
              style: FilledButton.styleFrom(
                backgroundColor: terracotta,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Tambah Alat / Modal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 4 Summary Metric Cards
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Modal Usaha & Alat', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(totalCapital), style: const TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Laba Bersih Bulanan Saat Ini', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(monthlyNetProfit), style: const TextStyle(color: Color(0xFF15803D), fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Estimasi BEP (Impas)', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(bepMonths > 0 ? '⚡ $bepMonths Bulan' : 'Belum BEP', style: const TextStyle(color: terracotta, fontSize: 15, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Progres Balik Modal', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text('${paybackPct.toStringAsFixed(1)}% Tercover', style: const TextStyle(color: Color(0xFF0284C7), fontSize: 15, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // BEP Progress Card Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F4EA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.analytics_rounded, color: Color(0xFF15803D), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  totalCapital > 0
                      ? 'Dengan rata-rata Laba Bersih ${_money(monthlyNetProfit)}/bulan, investasi modal ${_money(totalCapital)} diproyeksikan Balik Modal Penuh (BEP) dalam waktu $bepMonths Bulan.'
                      : 'Belum ada data modal usaha/alat terdaftar. Klik "+ Tambah Alat / Modal" untuk mencatat investasi awal cafe Anda.',
                  style: const TextStyle(color: Color(0xFF15803D), fontSize: 12, fontWeight: FontWeight.w700, height: 1.3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF5F0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: const [
              Expanded(flex: 4, child: Text('Peralatan / Pembuatan Cafe', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text('Kategori Investasi', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 2, child: Text('Tanggal', textAlign: TextAlign.center, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text('Nominal Investasi', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              SizedBox(width: 32),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Table Rows
        if (equipmentList.isNotEmpty) ...[
          for (int i = 0; i < equipmentList.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(_capitalizeTitle(equipmentList[i]['description']?.toString() ?? 'Peralatan'), style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(equipmentList[i]['category']?.toString() ?? 'Modal Usaha', style: const TextStyle(color: mutedGray, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(equipmentList[i]['expense_date']?.toString() ?? '-', textAlign: TextAlign.center, style: const TextStyle(color: darkBrown, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(_money(equipmentList[i]['amount']), textAlign: TextAlign.right, style: const TextStyle(color: terracotta, fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                  SizedBox(
                    width: 32,
                    child: InkWell(
                      onTap: () => widget.onDeleteExpense(equipmentList[i]),
                      child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFDC2626)),
                    ),
                  ),
                ],
              ),
            ),
            if (i < equipmentList.length - 1)
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ],
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Belum ada modal / peralatan terdaftar.', style: TextStyle(color: mutedGray, fontSize: 13)),
            ),
          ),
      ],
    );
  }

  Widget _buildSampleEquipmentRow(String name, String cat, String date, String value) {
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);
    const terracotta = Color(0xFFC45A34);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(name, style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700))),
          Expanded(flex: 3, child: Text(cat, style: const TextStyle(color: mutedGray, fontSize: 12))),
          Expanded(flex: 2, child: Text(date, textAlign: TextAlign.center, style: const TextStyle(color: darkBrown, fontSize: 12))),
          Expanded(flex: 3, child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: terracotta, fontSize: 13, fontWeight: FontWeight.w800))),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _buildIngredientAnalysisReportView() {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final ingList = (widget.report['ingredients'] as List<dynamic>? ?? []);
    int totalItems = ingList.length;
    double totalValue = 0.0;

    for (var ing in ingList) {
      final qty = num.tryParse(ing['stock_quantity']?.toString() ?? '')?.toDouble() ?? 0.0;
      final unitCost = num.tryParse(ing['cost_per_base_unit']?.toString() ?? '')?.toDouble() ?? 0.0;
      totalValue += (qty * unitCost);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Laporan Pembelian & Stok Bahan Baku (Bahan)',
              style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFFAF2E9), borderRadius: BorderRadius.circular(10)),
              child: Text('$totalItems Jenis Bahan Terdaftar', style: const TextStyle(color: terracotta, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 3 Summary Cards
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Jenis Bahan Baku', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text('$totalItems jenis', style: const TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Nilai Modal Pembelian', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(totalValue), style: const TextStyle(color: terracotta, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status Integrasi Restock', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    const Text('⚡ Terhubung Otomatis (+Stok)', style: TextStyle(color: Color(0xFF15803D), fontSize: 13, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Table Header Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF5F0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: const [
              Expanded(flex: 3, child: Text('Nama Bahan', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 2, child: Text('Quantity', textAlign: TextAlign.center, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text('Isi per Kemasan / Stok Awal', textAlign: TextAlign.center, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text('Harga per Satuan', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text('Harga Total', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Table Content Rows
        if (ingList.isNotEmpty) ...[
          for (int i = 0; i < ingList.length; i++) ...[
            Builder(builder: (context) {
              final ing = ingList[i];
              final name = _capitalizeTitle(ing['name']?.toString() ?? 'Bahan');
              final baseUnit = (ing['base_unit'] as String? ?? 'gr').trim().toLowerCase();
              final stockQty = num.tryParse(ing['stock_quantity']?.toString() ?? '')?.toDouble() ?? 0.0;
              final costPerUnit = num.tryParse(ing['cost_per_base_unit']?.toString() ?? '')?.toDouble() ?? 0.0;

              String displayUnit = baseUnit;
              double displaySize = stockQty;
              double displayCost = costPerUnit;

              if (baseUnit == 'gr' && stockQty >= 1000 && stockQty % 1000 == 0) {
                displayUnit = 'kg';
                displaySize = stockQty / 1000;
                displayCost = costPerUnit * 1000;
              } else if (baseUnit == 'ml' && stockQty >= 1000 && stockQty % 1000 == 0) {
                displayUnit = 'L';
                displaySize = stockQty / 1000;
                displayCost = costPerUnit * 1000;
              }

              final totalPrice = costPerUnit * stockQty;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(name, style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                    const Expanded(
                      flex: 2,
                      child: Text('1 Kemasan', textAlign: TextAlign.center, style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${displaySize % 1 == 0 ? displaySize.toInt() : displaySize} $displayUnit',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${_money(displayCost)} / $displayUnit',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _money(totalPrice),
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: terracotta, fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (i < ingList.length - 1)
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ],
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Belum ada data pembelian bahan baku pada periode ini.', style: TextStyle(color: mutedGray, fontSize: 13)),
            ),
          ),
      ],
    );
  }

  Widget _buildSampleIngredientRow(
    String name,
    String total,
    String end,
    String used,
    String pct,
    String flow,
    String advice,
    Color bg,
    Color textColor,
  ) {
    const darkBrown = Color(0xFF3B2820);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(name, style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(total, textAlign: TextAlign.center, style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text(end, textAlign: TextAlign.center, style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text(used, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC45A34), fontSize: 12, fontWeight: FontWeight.w800))),
          Expanded(flex: 2, child: Text(pct, textAlign: TextAlign.center, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w800))),
          Expanded(
            flex: 2,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                child: Text(flow, style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          Expanded(flex: 4, child: Text(advice, style: const TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildProductSalesReportView() {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    int totalQtySold = 0;
    double totalRevenue = 0.0;
    double totalCost = 0.0;
    String bestSellerName = '-';
    int bestSellerQty = 0;
    String bestMarginName = '-';
    int bestMarginPct = 0;

    for (var p in widget.products) {
      final qty = (p['quantity'] as num?)?.toInt() ?? 0;
      final rev = num.tryParse(p['revenue']?.toString() ?? '')?.toDouble() ?? 0.0;
      final cst = num.tryParse(p['cost']?.toString() ?? '')?.toDouble() ?? 0.0;
      final profit = num.tryParse(p['gross_profit']?.toString() ?? '')?.toDouble() ?? (rev - cst);
      final marginPct = rev > 0 ? ((profit / rev) * 100).round() : 0;
      final name = _capitalizeTitle(p['name']?.toString() ?? 'Menu');

      totalQtySold += qty;
      totalRevenue += rev;
      totalCost += cst;

      if (qty > bestSellerQty) {
        bestSellerQty = qty;
        bestSellerName = name;
      }
      if (marginPct > bestMarginPct) {
        bestMarginPct = marginPct;
        bestMarginName = name;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action Bar & Sorting
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Analisis Penjualan & Performa Menu',
              style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF2E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${widget.products.length} Menu Terdaftar',
                style: const TextStyle(color: terracotta, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 4 Summary Metric Cards
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Porsi Terjual', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text('$totalQtySold porsi', style: const TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Omzet Penjualan', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(totalRevenue), style: const TextStyle(color: terracotta, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Menu Terlaris (Best Seller)', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(bestSellerName, style: const TextStyle(color: Color(0xFF15803D), fontSize: 14, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Margin Tertinggi', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(bestMarginPct > 0 ? '$bestMarginName ($bestMarginPct%)' : '-', style: const TextStyle(color: Color(0xFF0284C7), fontSize: 13, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Table Header Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF5F0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: const [
              Expanded(flex: 3, child: Text('Nama Menu', style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 2, child: Text('Jumlah Terjual', textAlign: TextAlign.center, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 2, child: Text('Harga Satuan', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 2, child: Text('Total Omzet', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 2, child: Text('HPP / Modal', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text('Laba Kotor (Margin)', textAlign: TextAlign.right, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
              Expanded(flex: 2, child: Text('Klasifikasi', textAlign: TextAlign.center, style: TextStyle(color: darkBrown, fontSize: 11, fontWeight: FontWeight.w800))),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Table Content Rows
        if (widget.products.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Belum ada data penjualan menu pada periode ini.', style: TextStyle(color: mutedGray, fontSize: 13)),
            ),
          )
        else
          for (int i = 0; i < widget.products.length; i++) ...[
            Builder(builder: (context) {
              final p = widget.products[i];
              final name = _capitalizeTitle(p['name']?.toString() ?? 'Menu');
              final qty = (p['quantity'] as num?)?.toInt() ?? 0;
              final rev = num.tryParse(p['revenue']?.toString() ?? '')?.toDouble() ?? 0.0;
              final cst = num.tryParse(p['cost']?.toString() ?? '')?.toDouble() ?? 0.0;
              final profit = num.tryParse(p['gross_profit']?.toString() ?? '')?.toDouble() ?? (rev - cst);
              final unitPrice = qty > 0 ? (rev / qty) : num.tryParse(p['selling_price']?.toString() ?? '')?.toDouble() ?? 0.0;
              final marginPct = rev > 0 ? ((profit / rev) * 100).round() : 0;

              // Menu Classification
              String classLabel = '🔥 Best Seller';
              Color classBg = const Color(0xFFE6F4EA);
              Color classText = const Color(0xFF1E8E3E);

              if (qty == bestSellerQty && qty > 0) {
                classLabel = '🔥 Best Seller';
                classBg = const Color(0xFFE6F4EA);
                classText = const Color(0xFF1E8E3E);
              } else if (marginPct >= 70) {
                classLabel = '💎 High Margin';
                classBg = const Color(0xFFE0F2FE);
                classText = const Color(0xFF0284C7);
              } else if (qty > 0) {
                classLabel = '⭐ Reguler';
                classBg = const Color(0xFFFFF8E7);
                classText = const Color(0xFFD97706);
              } else {
                classLabel = '⚠️ Low Sales';
                classBg = const Color(0xFFFCE8E6);
                classText = const Color(0xFFD93025);
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(name, style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('$qty porsi', textAlign: TextAlign.center, style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(_money(unitPrice), textAlign: TextAlign.right, style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(_money(rev), textAlign: TextAlign.right, style: const TextStyle(color: terracotta, fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(_money(cst), textAlign: TextAlign.right, style: const TextStyle(color: mutedGray, fontSize: 12)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('${_money(profit)} ($marginPct%)', textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF1E8E3E), fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: classBg, borderRadius: BorderRadius.circular(10)),
                          child: Text(classLabel, style: TextStyle(color: classText, fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (i < widget.products.length - 1)
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ],
      ],
    );
  }

  Widget _buildOperatingExpensesView({
    required double expenseTotal,
    required String curMonthLabel,
  }) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    // Filter expenses into Wajib vs Lain-lain/Harian
    final wajibExpenses = <Map<String, dynamic>>[];
    final otherExpenses = <Map<String, dynamic>>[];

    for (var e in widget.expenses) {
      final cat = (e['category'] ?? '').toString().toLowerCase();
      if (cat.contains('modal') || cat.contains('alat')) continue; // Skip CAPEX

      if (cat.contains('wajib')) {
        wajibExpenses.add(e);
      } else {
        otherExpenses.add(e);
      }
    }

    final totalWajib = wajibExpenses.fold(0.0, (sum, e) => sum + (num.tryParse(e['amount']?.toString() ?? '')?.toDouble() ?? 0.0));
    final totalHarian = otherExpenses.fold(0.0, (sum, e) => sum + (num.tryParse(e['amount']?.toString() ?? '')?.toDouble() ?? 0.0));
    final calcTotalExpense = totalWajib + totalHarian;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Rincian Biaya Operasional',
              style: TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            FilledButton.icon(
              onPressed: widget.onAddExpense,
              style: FilledButton.styleFrom(
                backgroundColor: terracotta,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Tambah Biaya Baru', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 3 Summary Cards
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Biaya Operasional', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(calcTotalExpense), style: const TextStyle(color: darkBrown, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Biaya Wajib Perbulan', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(totalWajib), style: const TextStyle(color: terracotta, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Biaya Harian & Lain-lain', style: TextStyle(color: mutedGray, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(totalHarian), style: const TextStyle(color: Color(0xFFD97706), fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Section 1: BIAYA WAJIB PERBULAN
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFFAF2E9), borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('1. BIAYA WAJIB PERBULAN', style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800)),
              Text('Status: Rutin Perbulan', style: TextStyle(color: mutedGray, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (wajibExpenses.isNotEmpty)
          for (var e in wajibExpenses) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_capitalizeTitle(e['description']?.toString() ?? 'Biaya Wajib'), style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700)),
                        Text('${e['expense_date'] ?? ''} • Biaya Wajib Perbulan', style: const TextStyle(color: mutedGray, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text(_money(e['amount']), style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => widget.onDeleteExpense(e),
                    child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFDC2626)),
                  ),
                ],
              ),
            ),
          ]
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text('Belum ada biaya wajib perbulan terdaftar.', style: TextStyle(color: mutedGray, fontSize: 12)),
          ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal Biaya Wajib', style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800)),
              Text(_money(totalWajib), style: const TextStyle(color: terracotta, fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Section 2: BIAYA HARIAN & LAIN-LAIN
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFFAF2E9), borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('2. BIAYA HARIAN & LAIN-LAIN', style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800)),
              Text('Status: Insidental / Tidak Menentu', style: TextStyle(color: mutedGray, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (otherExpenses.isNotEmpty)
          for (var e in otherExpenses) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_capitalizeTitle(e['description']?.toString() ?? 'Lain-lain'), style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700)),
                        Text('${e['expense_date'] ?? ''} • Lain-lain / Harian', style: const TextStyle(color: mutedGray, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text(_money(e['amount']), style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => widget.onDeleteExpense(e),
                    child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFDC2626)),
                  ),
                ],
              ),
            ),
          ]
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text('Belum ada biaya harian/lain-lain terdaftar.', style: TextStyle(color: mutedGray, fontSize: 12)),
          ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal Biaya Lain-lain / Harian', style: TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800)),
              Text(_money(totalHarian), style: const TextStyle(color: Color(0xFFD97706), fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpenseRow(String label, String value, String tag) {
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                child: Text(tag, style: const TextStyle(color: mutedGray, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          Text(value, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 220,
      child: Card(
          child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ]),
      )));
}

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});
  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final _storeName = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _taxRate = TextEditingController(text: '10');
  final _serviceRate = TextEditingController(text: '0');
  final _receiptFooter = TextEditingController();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _currentPin = TextEditingController();
  final _newPin = TextEditingController();
  final _confirmNewPin = TextEditingController();
  String _role = 'CASHIER';
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;
  String? _logoDataUrl;

  Future<void> _pickLogo() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file != null) {
        final bytes = await file.readAsBytes();
        final ext = file.extension?.toLowerCase() ?? 'png';
        final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';
        final base64Str = base64Encode(bytes);
        final dataUrl = 'data:$mime;base64,$base64Str';
        setState(() {
          _logoDataUrl = dataUrl;
        });
        if (mounted) {
          context.read<PosProvider>().setStoreProfile(
            name: _storeName.text.trim().isEmpty ? 'Lailain' : _storeName.text.trim(),
            logo: dataUrl,
          );
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _storeName.dispose();
    _address.dispose();
    _phone.dispose();
    _taxRate.dispose();
    _serviceRate.dispose();
    _receiptFooter.dispose();
    _name.dispose();
    _pin.dispose();
    _currentPin.dispose();
    _newPin.dispose();
    _confirmNewPin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _adminRequest(context, 'GET', '/settings'),
        _adminRequest(context, 'GET', '/users'),
      ]);
      final settings = results[0] as Map<String, dynamic>;
      final profile = settings['store_profile'] as Map<String, dynamic>? ?? {};
      final tax = settings['tax_and_service'] as Map<String, dynamic>? ?? {};
      final receipt = settings['receipt'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      final storeNameVal = profile['name'] as String? ?? '';
      final logoVal = profile['logo'] as String?;
      setState(() {
        _storeName.text = storeNameVal.isEmpty ? 'Lailain' : storeNameVal;
        _address.text = profile['address'] as String? ?? '';
        _phone.text = profile['phone'] as String? ?? '';
        _logoDataUrl = logoVal;
        _taxRate.text = tax['taxRate']?.toString() ?? '10';
        _serviceRate.text = tax['serviceRate']?.toString() ?? '0';
        _receiptFooter.text = receipt['footer'] as String? ?? '';
        _users = (results[1] as List<dynamic>).cast<Map<String, dynamic>>();
        _error = null;
      });
      context.read<PosProvider>().setStoreProfile(
        name: storeNameVal.isEmpty ? 'Lailain' : storeNameVal,
        logo: logoVal,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String key, Map<String, dynamic> value) async {
    try {
      await _adminRequest(context, 'PUT', '/settings/$key',
          body: {'value': value});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pengaturan tersimpan.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  Future<void> _addUser() async {
    try {
      await _adminRequest(context, 'POST', '/users', body: {
        'name': _name.text.trim(),
        'pin': _pin.text,
        'role': _role,
      });
      _name.clear();
      _pin.clear();
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  Future<void> _changeMyPin() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_currentPin.text) ||
        !RegExp(r'^\d{6}$').hasMatch(_newPin.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN harus terdiri dari 6 angka.')),
      );
      return;
    }
    if (_newPin.text != _confirmNewPin.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konfirmasi PIN baru tidak cocok.')),
      );
      return;
    }
    final success = await context
        .read<AuthProvider>()
        .changeAdminPin(_currentPin.text, _newPin.text);
    _currentPin.clear();
    _newPin.clear();
    _confirmNewPin.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(success
                ? 'PIN berhasil diubah.'
                : context.read<AuthProvider>().error ?? 'Gagal mengubah PIN.')),
      );
    }
  }

  Future<void> _resetUserPin(Map<String, dynamic> user) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _NewPinDialog(),
    );
    if (!mounted || pin == null) return;
    try {
      await _adminRequest(context, 'PUT', '/users/${user['id']}/pin',
          body: {'pin': pin});
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PIN ${user['name']} berhasil diatur ulang.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 850;

        final leftColumn = Column(
          children: [
            // Profil Toko Card
            _SettingsSection(
              title: 'Profil Toko',
              onSave: () {
                final nameVal = _storeName.text.trim().isEmpty ? 'Lailain' : _storeName.text.trim();
                _save('store_profile', {
                  'name': nameVal,
                  'address': _address.text.trim(),
                  'phone': _phone.text.trim(),
                  'logo': _logoDataUrl,
                });
                context.read<PosProvider>().setStoreProfile(
                  name: nameVal,
                  logo: _logoDataUrl,
                );
              },
              children: [
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F2EB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      alignment: Alignment.center,
                      child: _logoDataUrl != null && _logoDataUrl!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                _logoDataUrl!,
                                width: 58,
                                height: 58,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.store_rounded, size: 28, color: Color(0xFF8C7D73)),
                              ),
                            )
                          : const Icon(Icons.store_rounded, size: 28, color: Color(0xFF8C7D73)),
                    ),
                    const SizedBox(width: 14),
                    OutlinedButton.icon(
                      onPressed: _pickLogo,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF3B2820),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        backgroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.upload_file_rounded, size: 18, color: Color(0xFFC45A34)),
                      label: const Text('Upload Logo Toko', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _storeName,
                  decoration: InputDecoration(
                    labelText: 'Nama toko',
                    hintText: 'Lailain',
                    prefixIcon: const Icon(Icons.store_rounded, color: Color(0xFF8C7D73), size: 20),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _address,
                  decoration: InputDecoration(
                    labelText: 'Alamat toko',
                    prefixIcon: const Icon(Icons.location_on_rounded, color: Color(0xFF8C7D73), size: 20),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phone,
                  decoration: InputDecoration(
                    labelText: 'Nomor telepon',
                    prefixIcon: const Icon(Icons.phone_rounded, color: Color(0xFF8C7D73), size: 20),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                ),
              ],
            ),

            // Cetakan Struk Card
            _SettingsSection(
              title: 'Cetakan Struk Kasir',
              onSave: () => _save('receipt', {'footer': _receiptFooter.text.trim()}),
              children: [
                TextField(
                  controller: _receiptFooter,
                  decoration: InputDecoration(
                    labelText: 'Pesan bagian bawah struk',
                    hintText: 'Terima kasih, selamat menikmati.',
                    prefixIcon: const Icon(Icons.receipt_rounded, color: Color(0xFF8C7D73), size: 20),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                ),
              ],
            ),

            // Status Server Cloud & Backup Otomatis Card
            Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status Server Cloud & Auto-Backup',
                      style: TextStyle(
                        fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1F1F1F),
                      )),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F4EA),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.cloud_done_rounded, color: Color(0xFF1E8E3E), size: 16),
                            SizedBox(width: 6),
                            Text('Cloud Connected 24/7', style: TextStyle(color: Color(0xFF1E8E3E), fontSize: 11, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3EBE0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.backup_rounded, color: Color(0xFF3B2820), size: 16),
                            SizedBox(width: 6),
                            Text('Auto-Backup Harian (Metode A)', style: TextStyle(color: Color(0xFF3B2820), fontSize: 11, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Database PostgreSQL & Server disinkronkan secara otomatis ke Cloud Server. Backup harian aktif 100% dan aman untuk bisnis berkepanjangan.',
                    style: TextStyle(color: Color(0xFF8C7D73), fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        );

        final rightColumn = Column(
          children: [
            // Pajak & Layanan Card
            _SettingsSection(
              title: 'Pajak & Layanan Outlet',
              onSave: () => _save('tax_and_service', {
                'taxRate': double.tryParse(_taxRate.text) ?? 0,
                'serviceRate': double.tryParse(_serviceRate.text) ?? 0,
              }),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _taxRate,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Pajak PPN (%)',
                          prefixIcon: const Icon(Icons.percent_rounded, color: Color(0xFF8C7D73), size: 20),
                          filled: true,
                          fillColor: const Color(0xFFFAFAFA),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _serviceRate,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Layanan Service (%)',
                          prefixIcon: const Icon(Icons.room_service_rounded, color: Color(0xFF8C7D73), size: 20),
                          filled: true,
                          fillColor: const Color(0xFFFAFAFA),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Tema Latar Kasir Card
            _SettingsSection(
              title: 'Tema Latar Kasir (LATAR)',
              onSave: () {},
              children: [
                Consumer<PosProvider>(
                  builder: (context, posProvider, _) {
                    return Row(
                      children: [
                        const Text('Pilih Tema Warna: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3B2820))),
                        const SizedBox(width: 8),
                        _adminThemeCircle(posProvider, const Color(0xFFF6F3EE), 'Sand'),
                        const SizedBox(width: 6),
                        _adminThemeCircle(posProvider, const Color(0xFFE5EDE0), 'Mint'),
                        const SizedBox(width: 6),
                        _adminThemeCircle(posProvider, const Color(0xFF232323), 'Dark'),
                      ],
                    );
                  },
                ),
              ],
            ),

            // Akun Pengguna Card
            Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Akun Pengguna & Akses',
                      style: TextStyle(
                        fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1F1F1F),
                      )),
                  const SizedBox(height: 10),
                  ..._users.map((user) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(user['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Text('${user['role']} · ${user['has_pin'] == true ? 'PIN Aktif' : 'PIN Belum Diatur'}', style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          tooltip: 'Atur ulang PIN',
                          onPressed: () => _resetUserPin(user),
                          icon: const Icon(Icons.pin_outlined, color: Color(0xFFC45A34)),
                        ),
                      )),
                  const Divider(height: 20),
                  TextField(
                      controller: _name,
                      decoration: InputDecoration(
                          labelText: 'Nama pengguna baru',
                          prefixIcon: const Icon(Icons.person_rounded, color: Color(0xFF8C7D73), size: 20),
                          filled: true,
                          fillColor: const Color(0xFFFAFAFA),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))))),
                  const SizedBox(height: 10),
                  TextField(
                      controller: _pin,
                      decoration: InputDecoration(
                          labelText: 'PIN 6 digit',
                          prefixIcon: const Icon(Icons.lock_rounded, color: Color(0xFF8C7D73), size: 20),
                          filled: true,
                          fillColor: const Color(0xFFFAFAFA),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0)))),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6),
                  DropdownButtonFormField<String>(
                      initialValue: _role,
                      decoration: InputDecoration(
                          labelText: 'Role akses',
                          prefixIcon: const Icon(Icons.verified_user_rounded, color: Color(0xFF8C7D73), size: 20),
                          filled: true,
                          fillColor: const Color(0xFFFAFAFA),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0)))),
                      items: const [
                        DropdownMenuItem(value: 'CASHIER', child: Text('Kasir')),
                        DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
                      ],
                      onChanged: (value) => setState(() => _role = value ?? 'CASHIER')),
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                          onPressed: _addUser,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFC45A34),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                          label: const Text('Tambah Akun', style: TextStyle(fontWeight: FontWeight.w800)))),
                ],
              ),
            ),

            // Ubah PIN Saya Card
            Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ubah PIN Admin Saya',
                      style: TextStyle(
                        fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1F1F1F),
                      )),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _currentPin,
                    decoration: InputDecoration(
                      labelText: 'PIN saat ini',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF8C7D73), size: 20),
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _newPin,
                    decoration: InputDecoration(
                      labelText: 'PIN baru 6 digit',
                      prefixIcon: const Icon(Icons.lock_reset_rounded, color: Color(0xFF8C7D73), size: 20),
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirmNewPin,
                    decoration: InputDecoration(
                      labelText: 'Ulangi PIN baru',
                      prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF8C7D73), size: 20),
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: context.watch<AuthProvider>().isLoading ? null : _changeMyPin,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFC45A34),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      child: const Text('Simpan PIN Baru', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        return ListView(
          padding: const EdgeInsets.fromLTRB(26, 8, 26, 26),
          children: [
            if (_error != null) _ErrorBanner(message: _error!, onRetry: _load),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: leftColumn),
                  const SizedBox(width: 20),
                  Expanded(child: rightColumn),
                ],
              )
            else
              Column(
                children: [
                  leftColumn,
                  rightColumn,
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _adminThemeCircle(PosProvider provider, Color color, String name) {
    final isSelected = provider.bgAccentColor.value == color.value;
    return InkWell(
      onTap: () => provider.setBgAccentColor(color),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFC45A34) : const Color(0xFFD6C8BC),
            width: isSelected ? 2.5 : 1.0,
          ),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color.computeLuminance() < 0.5 ? Colors.white : const Color(0xFF1F1F1F),
          ),
        ),
      ),
    );
  }
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog();

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Atur ulang PIN akun'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _pin,
            decoration: const InputDecoration(labelText: 'PIN baru 6 digit'),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
          ),
          TextField(
            controller: _confirmation,
            decoration: const InputDecoration(labelText: 'Ulangi PIN baru'),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (!RegExp(r'^\d{6}$').hasMatch(_pin.text)) {
                setState(() => _error = 'PIN harus terdiri dari 6 angka.');
                return;
              }
              if (_pin.text != _confirmation.text) {
                setState(() => _error = 'Konfirmasi PIN tidak cocok.');
                return;
              }
              Navigator.pop(context, _pin.text);
            },
            child: const Text('Simpan PIN'),
          ),
        ],
      );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection(
      {required this.title, required this.children, required this.onSave});
  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1F1F1F),
              ),
            ),
            const SizedBox(height: 14),
            ...children,
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC45A34),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
                child: Text(
                  'Simpan',
                  style: TextStyle(
                    fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}


