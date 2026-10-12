import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../controllers/auth_provider.dart';
import 'admin_modules.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key, this.showSidebar = false, this.initialIndex = 0});

  final bool showSidebar;
  final int initialIndex;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  static const _baseUrl = String.fromEnvironment(
    'POS_API_URL',
    defaultValue: 'http://127.0.0.1:3000/api/v1',
  );
  int _selectedIndex = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _dashboard = {};
  String _topFilter = 'today'; // 'today', 'week', 'month'

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    Future.microtask(_loadDashboard);
  }

  Future<void> _loadDashboard() async {
    final token = context.read<AuthProvider>().token;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/dashboard'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(body['message'] ?? 'Gagal memuat dashboard.');
      }
      if (!mounted) return;
      setState(() {
        _dashboard = body['data'] as Map<String, dynamic>;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final font = GoogleFonts.bricolageGrotesque().fontFamily;

    if (!widget.showSidebar) {
      return Theme(
        data: Theme.of(context).copyWith(
          textTheme: GoogleFonts.bricolageGrotesqueTextTheme(Theme.of(context).textTheme),
        ),
        child: Container(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Admin Workspace Header & Navigation Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 20, 26, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Workspace.',
                              style: TextStyle(
                                fontFamily: font,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1F1F1F),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Kelola produk, bahan baku, transaksi, laporan, dan pengaturan outlet',
                              style: TextStyle(
                                fontFamily: font,
                                color: const Color(0xFF8C7D73),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5EBE1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFEADBCE)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFC45A34), size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    auth.user?.name ?? 'Admin',
                                    style: TextStyle(
                                      fontFamily: font,
                                      color: const Color(0xFF3B2820),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: auth.logout,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFD93025),
                                side: const BorderSide(color: Color(0xFFFCE8E6)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                backgroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.logout_rounded, size: 16),
                              label: Text(
                                'Keluar Admin',
                                style: TextStyle(
                                  fontFamily: font,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Admin Navigation Tabs
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildAdminTab(0, 'Ringkasan', Icons.dashboard_outlined),
                          _buildAdminTab(1, 'Produk', Icons.inventory_2_outlined),
                          _buildAdminTab(2, 'Stok Bahan', Icons.scale_outlined),
                          _buildAdminTab(3, 'Transaksi', Icons.receipt_long_outlined),
                          _buildAdminTab(4, 'Laporan & Jurnal', Icons.bar_chart_outlined),
                          _buildAdminTab(5, 'Pengaturan', Icons.settings_outlined),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Active Admin Content Body
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: null,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.15),
            radius: 1.15,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFFAF2E9),
              Color(0xFFF0DDD0),
              Color(0xFFE2B298),
            ],
            stops: [0.0, 0.35, 0.70, 1.0],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              _buildAdminSidebar(auth),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminSidebar(AuthProvider auth) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Container(
      width: 228,
      margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 22, 14, 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.7),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6E4F3D).withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Admin Workspace Avatar Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 24),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: const Color(0xFFF5EBE1),
                        child: const Icon(Icons.admin_panel_settings_rounded,
                            color: terracotta, size: 22),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              auth.user?.name ?? 'Admin',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: darkBrown,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              'ADMIN AREA',
                              style: TextStyle(
                                color: terracotta,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 11, bottom: 9),
                  child: Text('WORKSPACE',
                      style: TextStyle(
                          color: mutedGray,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1)),
                ),
                _buildSidebarTile(Icons.dashboard_outlined, 'Dashboard', 0),
                _buildSidebarTile(Icons.inventory_2_outlined, 'Produk', 1),
                _buildSidebarTile(Icons.scale_outlined, 'Stok bahan', 2),
                _buildSidebarTile(Icons.receipt_long_outlined, 'Transaksi', 3),
                _buildSidebarTile(Icons.bar_chart_outlined, 'Laporan', 4),
                _buildSidebarTile(Icons.settings_outlined, 'Pengaturan', 5),
                const Spacer(),

                // Logout Button Tile
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(Icons.logout_rounded,
                        size: 19, color: Color(0xFFD93025)),
                    title: const Text('Keluar',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD93025))),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    dense: true,
                    onTap: auth.logout,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarTile(IconData icon, String title, int index) {
    final isActive = _selectedIndex == index;
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: Icon(icon, size: 19, color: isActive ? terracotta : darkBrown),
          title: Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  color: isActive ? terracotta : darkBrown)),
          selected: isActive,
          selectedTileColor: const Color(0xFFF3EBE0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          dense: true,
          onTap: () => setState(() => _selectedIndex = index),
        ),
      ),
    );
  }

  Widget _buildAdminTab(int index, String label, IconData icon) {
    final isActive = _selectedIndex == index;
    final font = GoogleFonts.bricolageGrotesque().fontFamily;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1F1F1F) : const Color(0xFFF5F2EB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? const Color(0xFF1F1F1F) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: isActive ? Colors.white : const Color(0xFF8C7D73)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: font,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isActive ? Colors.white : const Color(0xFF3B2820),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_selectedIndex == 1) return const AdminProductsPage();
    if (_selectedIndex == 2) return const AdminIngredientsPage();
    if (_selectedIndex == 3) return const AdminTransactionsPage();
    if (_selectedIndex == 4) return const AdminReportsPage();
    if (_selectedIndex == 5) return const AdminSettingsPage();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _loadDashboard, child: const Text('Coba lagi')),
        ]),
      );
    }

    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    final salesToday = num.tryParse(_dashboard['salesToday']?.toString() ?? '')?.toInt() ?? 0;
    final salesYesterday = num.tryParse(_dashboard['salesYesterday']?.toString() ?? '')?.toInt() ?? 0;
    final transactionsToday = num.tryParse(_dashboard['transactionsToday']?.toString() ?? '')?.toInt() ?? 0;
    final grossProfitToday = num.tryParse(_dashboard['grossProfitToday']?.toString() ?? '')?.toInt() ?? (salesToday * 0.65).round();
    final marginPercent = num.tryParse(_dashboard['marginPercent']?.toString() ?? '')?.toInt() ?? 65;
    final lowStockCount = num.tryParse(_dashboard['lowStockCount']?.toString() ?? '')?.toInt() ?? 0;
    final lowStock = (_dashboard['lowStockIngredients'] as List<dynamic>? ?? []);
    final recentTransactions = (_dashboard['recentTransactions'] as List<dynamic>? ?? []);
    final hourlySales = (_dashboard['hourlySales'] as List<dynamic>? ?? []);
    final topSelling = (_dashboard['topSelling'] as Map<String, dynamic>? ?? {});

    final avgTransaction = transactionsToday > 0 ? (salesToday / transactionsToday).round() : 0;
    final salesDiffText = _salesDiffPercentage(salesToday, salesYesterday);

    // Process hourly chart
    final Map<int, double> hourlyMap = {};
    int peakHour = 12;
    double peakAmount = 0.0;
    for (var item in hourlySales) {
      final h = num.tryParse(item['hour']?.toString() ?? '')?.toInt() ?? 0;
      final t = num.tryParse(item['total']?.toString() ?? '')?.toDouble() ?? 0.0;
      hourlyMap[h] = t;
      if (t > peakAmount) {
        peakAmount = t;
        peakHour = h;
      }
    }

    // Process top selling items
    final List<dynamic> topList = (topSelling[_topFilter] as List<dynamic>? ?? []);
    String topTitle = 'Menu Terlaris Hari Ini';
    if (_topFilter == 'week') topTitle = 'Menu Terlaris Minggu Ini';
    if (_topFilter == 'month') topTitle = 'Menu Terlaris Bulan Ini';

    int maxTopQty = 1;
    for (var item in topList) {
      final qty = num.tryParse(item['total_quantity']?.toString() ?? '')?.toInt() ?? 0;
      if (qty > maxTopQty) maxTopQty = qty;
    }

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Top Row: 4 Metric Cards (Expanded Row for 100% Left-Right Alignment)
          Row(
            children: [
              // Card 1: Penjualan Hari Ini
              Expanded(
                child: _AdminMetricCard(
                  icon: Icons.trending_up_rounded,
                  iconBg: const Color(0xFFF5EBE1),
                  iconColor: terracotta,
                  label: 'Penjualan hari ini',
                  value: _money(salesToday),
                  badgeText: salesDiffText,
                  badgeBg: const Color(0xFFE6F4EA),
                  badgeTextColor: const Color(0xFF1E8E3E),
                ),
              ),
              const SizedBox(width: 16),

              // Card 2: Transaksi
              Expanded(
                child: _AdminMetricCard(
                  icon: Icons.receipt_long_rounded,
                  iconBg: const Color(0xFFF5EBE1),
                  iconColor: terracotta,
                  label: 'Transaksi',
                  value: '$transactionsToday',
                  badgeText: 'Rata-rata ${_money(avgTransaction)}',
                  badgeBg: const Color(0xFFF3EBE0),
                  badgeTextColor: darkBrown,
                ),
              ),
              const SizedBox(width: 16),

              // Card 3: Laba kotor (estimasi)
              Expanded(
                child: _AdminMetricCard(
                  icon: Icons.percent_rounded,
                  iconBg: const Color(0xFFF5EBE1),
                  iconColor: terracotta,
                  label: 'Laba kotor (estimasi)',
                  value: _money(grossProfitToday),
                  badgeText: 'Margin $marginPercent%',
                  badgeBg: const Color(0xFFE6F4EA),
                  badgeTextColor: const Color(0xFF1E8E3E),
                ),
              ),
              const SizedBox(width: 16),

              // Card 4: Bahan menipis
              Expanded(
                child: _AdminMetricCard(
                  icon: Icons.warning_amber_rounded,
                  iconBg: const Color(0xFFFCE8E6),
                  iconColor: const Color(0xFFD93025),
                  label: 'Bahan menipis',
                  value: '$lowStockCount bahan',
                  valueColor: const Color(0xFFD93025),
                  badgeText: lowStock.isEmpty
                      ? 'Semua bahan aman'
                      : lowStock
                          .take(2)
                          .map((e) => _capitalizeTitle((e as Map<String, dynamic>)['name']?.toString() ?? ''))
                          .join(', '),
                  badgeBg: const Color(0xFFFCE8E6),
                  badgeTextColor: const Color(0xFFD93025),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Main Content Grid (3 Columns Equal Height Alignment)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Column 1 (Left Card): Penjualan per Jam
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Penjualan per Jam',
                                  style: TextStyle(
                                    color: darkBrown,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  peakAmount > 0
                                      ? 'Jam tersibuk ${peakHour.toString().padLeft(2, '0')}:00 dengan ${_money(peakAmount)}'
                                      : 'Belum ada data transaksi hari ini',
                                  style: const TextStyle(
                                      color: mutedGray, fontSize: 12),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3EBE0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Hari ini',
                                style: TextStyle(
                                  color: darkBrown,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Hourly Bar Chart
                        SizedBox(
                          height: 190,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (int h = 8; h <= 19; h++) ...[
                                Builder(builder: (context) {
                                  final amount = hourlyMap[h] ?? 0.0;
                                  final label = h.toString().padLeft(2, '0');
                                  final isPeak = (h == peakHour && peakAmount > 0);
                                  final double barHeight = peakAmount > 0
                                      ? ((amount / peakAmount) * 130).clamp(18.0, 130.0)
                                      : 24.0;
                                  final labelText = amount > 0
                                      ? (amount >= 1000 ? '${(amount / 1000).round()}k' : '${amount.round()}')
                                      : '';
                                  return _BarItem(
                                    label,
                                    barHeight,
                                    labelText,
                                    isPeak: isPeak,
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Column 2 (Middle Card): Menu Terlaris (Hari Ini / Perminggu / Perbulan)
                Expanded(
                  flex: 3,
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
                            Expanded(
                              child: Text(
                                topTitle,
                                style: const TextStyle(
                                  color: darkBrown,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Filter Dropdown: Hari ini, Perminggu, Perbulan
                            PopupMenuButton<String>(
                              initialValue: _topFilter,
                              onSelected: (val) =>
                                  setState(() => _topFilter = val),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3EBE0),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _topFilter == 'today'
                                          ? 'Hari ini'
                                          : (_topFilter == 'week'
                                              ? 'Perminggu'
                                              : 'Perbulan'),
                                      style: const TextStyle(
                                        color: darkBrown,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.arrow_drop_down_rounded,
                                        size: 18, color: darkBrown),
                                  ],
                                ),
                              ),
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                    value: 'today',
                                    child: Text('Hari ini',
                                        style: TextStyle(fontSize: 12))),
                                PopupMenuItem(
                                    value: 'week',
                                    child: Text('Perminggu',
                                        style: TextStyle(fontSize: 12))),
                                PopupMenuItem(
                                    value: 'month',
                                    child: Text('Perbulan',
                                        style: TextStyle(fontSize: 12))),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (topList.isEmpty)
                          const Expanded(
                            child: Center(
                              child: Text(
                                'Belum ada data penjualan.',
                                style: TextStyle(
                                    color: mutedGray, fontSize: 12),
                              ),
                            ),
                          )
                        else
                          Column(
                            children: [
                              for (int i = 0; i < topList.length; i++) ...[
                                Builder(builder: (context) {
                                  final item = topList[i];
                                  final name = _capitalizeTitle(
                                      item['name'] as String? ?? 'Produk');
                                  final qty = num.tryParse(item['total_quantity']?.toString() ?? '')?.toInt() ?? 0;
                                  final ratio =
                                      (qty / maxTopQty).clamp(0.1, 1.0);
                                  return Padding(
                                    padding: EdgeInsets.only(
                                        bottom: i < topList.length - 1 ? 12 : 0),
                                    child: _TopMenuRow(
                                      rank: i + 1,
                                      name: name,
                                      portion: '$qty porsi',
                                      progress: ratio,
                                      isTop: i == 0,
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Column 3 (Right Column): 2 Stacked Cards (Equal Height Expansion)
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      // Top Card: Stok Menipis
                      Expanded(
                        child: Container(
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
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Stok Menipis',
                                    style: TextStyle(
                                      color: darkBrown,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _selectedIndex = 2),
                                    style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact),
                                    child: const Text('Lihat semua',
                                        style: TextStyle(
                                            color: terracotta,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (lowStock.isEmpty)
                                const Expanded(
                                  child: Center(
                                    child: Text('Semua bahan aman',
                                        style: TextStyle(
                                            color: mutedGray, fontSize: 12)),
                                  ),
                                )
                              else
                                Column(
                                  children: [
                                    for (int i = 0; i < lowStock.take(2).length; i++) ...[
                                      Builder(builder: (context) {
                                        final item = lowStock[i];
                                        final name = _capitalizeTitle(
                                            item['name'] as String? ?? 'Bahan');
                                        final stockQty = num.tryParse(item['stock_quantity']?.toString() ?? '')?.toDouble() ?? 0.0;
                                        final threshold = num.tryParse(item['low_stock_threshold']?.toString() ?? '')?.toDouble() ?? 0.0;
                                        final unit = _formatUnitDisplay(item['base_unit'] as String?);
                                        final ratio = (threshold > 0) ? (stockQty / threshold).clamp(0.1, 1.0) : 0.8;
                                        return Padding(
                                          padding: EdgeInsets.only(bottom: i == 0 ? 10 : 0),
                                          child: _LowStockRow(
                                            name: name,
                                            stock: '${stockQty.round()} / ${threshold.round()} $unit',
                                            progress: ratio,
                                          ),
                                        );
                                      }),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Bottom Card: Transaksi Terakhir
                      Expanded(
                        child: Container(
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
                              const Text(
                                'Transaksi Terakhir',
                                style: TextStyle(
                                  color: darkBrown,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (recentTransactions.isEmpty)
                                const Expanded(
                                  child: Center(
                                    child: Text('Belum ada transaksi',
                                        style: TextStyle(
                                            color: mutedGray, fontSize: 12)),
                                  ),
                                )
                              else
                                Column(
                                  children: [
                                    for (int i = 0; i < recentTransactions.take(3).length; i++) ...[
                                      Builder(builder: (context) {
                                        final tx = recentTransactions[i];
                                        final code = '#${tx['order_number'] ?? 'A-${tx['id']?.toString().substring(0, 4) ?? '0000'}'}';
                                        final timeStr = _formatTime(tx['created_at']);
                                        final method = tx['payment_method'] as String? ?? 'Tunai';
                                        final priceVal = num.tryParse(tx['total_price']?.toString() ?? '')?.toDouble() ?? 0.0;
                                        return Padding(
                                          padding: EdgeInsets.only(bottom: i < recentTransactions.take(3).length - 1 ? 8 : 0),
                                          child: _RecentOrderRow(
                                            code: code,
                                            time: timeStr,
                                            method: method,
                                            price: _money(priceVal),
                                          ),
                                        );
                                      }),
                                    ],
                                  ],
                                ),
                            ],
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
    );
  }

  String _salesDiffPercentage(int today, int yesterday) {
    if (yesterday == 0) {
      return today > 0 ? '+100% vs kemarin' : '0% vs kemarin';
    }
    final diff = ((today - yesterday) / yesterday * 100).round();
    final sign = diff >= 0 ? '+' : '';
    return '$sign$diff% vs kemarin';
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

  String _capitalizeTitle(String text) {
    if (text.trim().isEmpty) return text;
    return text.trim().split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
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

  String _money(dynamic value) {
    final amount = num.tryParse(value?.toString() ?? '')?.round() ?? 0;
    final formatted = amount
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
    return 'Rp $formatted';
  }
}

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
    required this.badgeText,
    required this.badgeBg,
    required this.badgeTextColor,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final Color? valueColor;
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
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      color: mutedGray,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? darkBrown,
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

class _BarItem extends StatelessWidget {
  const _BarItem(this.time, this.height, this.label, {this.isPeak = false});

  final String time;
  final double height;
  final String label;
  final bool isPeak;

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const mutedGray = Color(0xFF8C7D73);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (label.isNotEmpty)
          Text(
            label,
            style: TextStyle(
              color: isPeak ? terracotta : mutedGray,
              fontSize: 10,
              fontWeight: isPeak ? FontWeight.w800 : FontWeight.w600,
            ),
          )
        else
          const SizedBox(height: 14),
        const SizedBox(height: 4),
        Container(
          width: 22,
          height: height / 2.2,
          decoration: BoxDecoration(
            color: isPeak ? terracotta : const Color(0xFFEEDBCE),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          time,
          style: TextStyle(
            color: isPeak ? terracotta : mutedGray,
            fontSize: 10,
            fontWeight: isPeak ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TopMenuRow extends StatelessWidget {
  const _TopMenuRow({
    required this.rank,
    required this.name,
    required this.portion,
    required this.progress,
    this.isTop = false,
  });

  final int rank;
  final String name;
  final String portion;
  final double progress;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isTop ? terracotta : const Color(0xFFF3EBE0),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: isTop ? Colors.white : darkBrown,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: darkBrown,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              portion,
              style: const TextStyle(color: mutedGray, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: const Color(0xFFEFE6DD),
            valueColor: AlwaysStoppedAnimation<Color>(
              isTop ? terracotta : const Color(0xFFE0CFC2),
            ),
          ),
        ),
      ],
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({
    required this.name,
    required this.stock,
    required this.progress,
  });

  final String name;
  final String stock;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const darkBrown = Color(0xFF3B2820);
    const redColor = Color(0xFFD93025);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name,
                style: const TextStyle(
                    color: darkBrown,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            Text(stock,
                style: const TextStyle(
                    color: redColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: const Color(0xFFEFE6DD),
            valueColor: const AlwaysStoppedAnimation<Color>(redColor),
          ),
        ),
      ],
    );
  }
}

class _RecentOrderRow extends StatelessWidget {
  const _RecentOrderRow({
    required this.code,
    required this.time,
    required this.method,
    required this.price,
  });

  final String code;
  final String time;
  final String method;
  final String price;

  @override
  Widget build(BuildContext context) {
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: darkBrown,
                    fontSize: 12,
                    fontWeight: FontWeight.w800),
              ),
              Text(time, style: const TextStyle(color: mutedGray, fontSize: 10)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF3EBE0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            method,
            style: const TextStyle(
                color: darkBrown, fontSize: 9, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          price,
          style: const TextStyle(
              color: darkBrown, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
