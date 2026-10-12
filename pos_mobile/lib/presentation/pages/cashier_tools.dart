import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show Printing;
import 'package:provider/provider.dart';
import '../controllers/auth_provider.dart';

const _cashierApiUrl = String.fromEnvironment(
  'POS_API_URL',
  defaultValue: 'http://127.0.0.1:3000/api/v1',
);

Future<dynamic> _cashierRequest(
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
  final uri = Uri.parse('$_cashierApiUrl$path');
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

String _formatCashierMoney(dynamic value) {
  final amount = num.tryParse(value?.toString() ?? '')?.round() ?? 0;
  final formatted = amount
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return 'Rp $formatted';
}

class CashierIngredientsPage extends StatefulWidget {
  const CashierIngredientsPage({super.key});

  @override
  State<CashierIngredientsPage> createState() =>
      _CashierIngredientsPageState();
}

class _CashierIngredientsPageState extends State<CashierIngredientsPage> {
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
      final data = await _cashierRequest(context, 'GET', '/ingredients')
          as List<dynamic>;
      if (mounted) {
        setState(() {
          _items = data.cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEdit([Map<String, dynamic>? ingredient]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AddIngredientDialog(ingredient: ingredient),
    );
    if (!mounted || result == null) return;
    if (result['delete'] == true && ingredient != null) {
      await _delete(ingredient);
      return;
    }
    try {
      if (ingredient == null) {
        await _cashierRequest(context, 'POST', '/ingredients', body: result);
      } else {
        await _cashierRequest(
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
      builder: (_) => _CashierRestockDialog(ingredient: item),
    );
    if (!mounted || values == null) return;
    try {
      await _cashierRequest(
        context,
        'POST',
        '/ingredients/${item['id']}/restock',
        body: values,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
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
      await _cashierRequest(context, 'DELETE', '/ingredients/${item['id']}');
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

          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: ListTile(
                title: Text(_error!),
                trailing: IconButton(
                    onPressed: _load, icon: const Icon(Icons.refresh)),
              ),
            ),

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

class _AddIngredientDialog extends StatefulWidget {
  const _AddIngredientDialog({this.ingredient});
  final Map<String, dynamic>? ingredient;

  @override
  State<_AddIngredientDialog> createState() => __AddIngredientDialogState();
}

class __AddIngredientDialogState extends State<_AddIngredientDialog> {
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
      text: isEdit && totalPurchase > 0 ? _formatCashierMoneyNoSymbol(totalPurchase.round()) : '',
    );
    _costPerBaseUnit = TextEditingController(
      text: isEdit && unitCost > 0 ? _formatCashierMoneyNoSymbol(unitCost.round()) : '',
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

    final totalPurchasePrice = double.tryParse(_totalPurchasePrice.text.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0;
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

              // Quantity & Nominal per Kemasan / Stok Awal (dengan Pilihan Satuan Langsung)
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
                      final formatted = _formatCashierMoneyNoSymbol(clean);
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
                            _formatCashierMoney(pricePerPackage),
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

String _formatCashierMoneyNoSymbol(dynamic raw) {
  if (raw == null) return '';
  final str = raw.toString().replaceAll('.', '').replaceAll(',', '').trim();
  final numVal = int.tryParse(str);
  if (numVal == null) return '';
  return numVal.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
}

class _CashierRestockDialog extends StatefulWidget {
  const _CashierRestockDialog({required this.ingredient});
  final Map<String, dynamic> ingredient;

  @override
  State<_CashierRestockDialog> createState() => _CashierRestockDialogState();
}

class _CashierRestockDialogState extends State<_CashierRestockDialog> {
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
      text: defaultPrice > 0 ? _formatCashierMoneyNoSymbol(defaultPrice) : '',
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

    final parsedPkgCount = double.tryParse(_packageCount.text.trim()) ?? 0.0;
    final pkgCount = (parsedPkgCount > 0) ? parsedPkgCount : 1.0;

    final parsedContent = double.tryParse(_contentPerPackage.text.trim()) ?? 0.0;
    final defaultSize = (_restockUnit == 'kg' || _restockUnit == 'L') ? 1.0 : 1000.0;
    final contentPerPkg = (parsedContent > 0) ? parsedContent : defaultSize;

    final parsedPrice = double.tryParse(_pricePerPackage.text.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0.0;
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
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
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
                    final formatted = _formatCashierMoneyNoSymbol(clean);
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
                        Text(_formatCashierMoney(totalPurchaseCost),
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
                              ? '${_formatCashierMoney(calculatedPricePerBaseUnit)}/gr (${_formatCashierMoney(calculatedPricePerBaseUnit * 1000)}/kg)'
                              : ((baseUnit == 'ml')
                                  ? '${_formatCashierMoney(calculatedPricePerBaseUnit)}/ml (${_formatCashierMoney(calculatedPricePerBaseUnit * 1000)}/L)'
                                  : '${_formatCashierMoney(calculatedPricePerBaseUnit)}/$baseUnit'),
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

class CashierTransactionsPage extends StatefulWidget {
  const CashierTransactionsPage({super.key});

  @override
  State<CashierTransactionsPage> createState() =>
      _CashierTransactionsPageState();
}

class _CashierTransactionsPageState extends State<CashierTransactionsPage> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredOrders {
    if (_searchQuery.trim().isEmpty) return _orders;
    final query = _searchQuery.toLowerCase().trim();
    return _orders.where((order) {
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
      final data = await _cashierRequest(context, 'GET', '/transactions')
          as List<dynamic>;
      if (mounted) {
        setState(() {
          _orders = data.cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan transaksi?'),
        content: Text(
            'Stok resep transaksi ${order['order_number'] ?? order['id']} akan dikembalikan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Kembali')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Batalkan')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await _cashierRequest(
        context,
        'POST',
        '/transactions/${order['id']}/cancel',
        body: const {'note': 'Dibatalkan oleh kasir'},
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _print(Map<String, dynamic> order) async {
    final document = pw.Document();
    final lines =
        (order['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    document.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
              child: pw.Text('STRUK TRANSAKSI',
                  style: const pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 8),
          pw.Text('No: ${order['order_number'] ?? order['id']}'),
          pw.Text('Waktu: ${order['created_at']}'),
          pw.Divider(),
          ...lines.map((item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                        child:
                            pw.Text('${item['name']} × ${item['quantity']}')),
                    pw.Text(_formatCashierMoney(item['subtotal'])),
                  ],
                ),
              )),
          pw.Divider(),
          pw.Text('Pembayaran: ${order['payment_method']}'),
          pw.Text('Total: ${_formatCashierMoney(order['total_price'])}'),
          pw.Text('Dibayar: ${_formatCashierMoney(order['paid_amount'])}'),
          pw.Text('Kembalian: ${_formatCashierMoney(order['change_amount'])}'),
        ],
      ),
    ));
    await Printing.layoutPdf(onLayout: (_) => document.save());
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
                pw.Text(_formatCashierMoney(item['subtotal']), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
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
              pw.Text(_formatCashierMoney(totalPrice), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Dibayar:', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(_formatCashierMoney(paidAmount), style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          if (changeAmount > 0) ...[
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Kembalian:', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(_formatCashierMoney(changeAmount), style: const pw.TextStyle(fontSize: 8)),
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

  void _showDetails(Map<String, dynamic> order) {
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
                                '${item['quantity'] ?? 1} x ${_formatCashierMoney(item['unitPrice'])}',
                                style: const TextStyle(color: mutedGray, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Text(_formatCashierMoney(item['subtotal']), style: const TextStyle(color: darkBrown, fontSize: 13, fontWeight: FontWeight.w800)),
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
                    Text(_formatCashierMoney(order['total_price']), style: const TextStyle(color: terracotta, fontSize: 15, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dibayar', style: TextStyle(color: mutedGray, fontSize: 12)),
                    Text(_formatCashierMoney(order['paid_amount']), style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                if ((num.tryParse(order['change_amount']?.toString() ?? '') ?? 0) > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Kembalian', style: TextStyle(color: mutedGray, fontSize: 12)),
                      Text(_formatCashierMoney(order['change_amount']), style: const TextStyle(color: darkBrown, fontSize: 12, fontWeight: FontWeight.w700)),
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
                        'Transaksi',
                        style: TextStyle(
                          color: darkBrown,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Riwayat semua transaksi penjualan',
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
              ],
            ),
          ),

          // Search & Date Filter Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
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
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
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
                    if (selected != null) {
                      final formattedDate =
                          '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
                      setState(() => _searchQuery = formattedDate);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: darkBrown,
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    backgroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: const Text('Filter Tanggal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                if (_searchQuery.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _searchQuery = ''),
                    child: const Text('Hapus Filter', style: TextStyle(color: Color(0xFFD93025))),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: ListTile(title: Text(_error!)),
            ),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_orders.isEmpty)
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
                                  width: 50,
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
                              final orderNumber = _formatOrderCode(order, filtered.length - index);
                              final dateStr = _formatDateTime(order['created_at']);
                              final itemsList = (order['items'] as List<dynamic>? ?? []);
                              final itemCount = itemsList.length;
                              final paymentMethod = (order['payment_method'] ?? 'CASH').toString().toUpperCase();
                              final totalPrice = order['total_price'] ?? 0;

                              // Check if we need to render a date divider (if this date is different from previous)
                              bool showDateDivider = false;
                              String currentDay = dateStr.split(' ')[0]; // e.g. "11/10/2026"
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
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                                      color: const Color(0xFFF8FAFC),
                                      child: Text(
                                        currentDay,
                                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                                      ),
                                    ),
                                  if (!showDateDivider && index > 0)
                                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    child: Row(
                                      children: [
                                        // No Struk
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            orderNumber,
                                            style: const TextStyle(
                                                color: darkBrown,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                        // Waktu
                                        Expanded(
                                          flex: 3,
                                          child: Text(dateStr.split(' ').last,
                                              style: const TextStyle(
                                                  color: mutedGray, fontSize: 12)),
                                        ),
                                        // Item
                                        Expanded(
                                          flex: 2,
                                          child: Text('$itemCount item',
                                              style: const TextStyle(
                                              color: mutedGray, fontSize: 12)),
                                    ),
                                    // Bayar
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
                                    // Total
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        _formatCashierMoney(totalPrice),
                                        style: const TextStyle(
                                            color: terracotta,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    // Aksi
                                    SizedBox(
                                      width: 50,
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: InkWell(
                                          onTap: () => _showDetails(order),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                                Icons.remove_red_eye_outlined,
                                                size: 18,
                                                color: darkBrown),
                                          ),
                                        ),
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
      final res = await _cashierRequest(context, 'GET', '/ingredients/restock-history');
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
                        Text(_formatCashierMoney(_totalPurchaseMonth),
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
                                  _formatCashierMoney(cost),
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
