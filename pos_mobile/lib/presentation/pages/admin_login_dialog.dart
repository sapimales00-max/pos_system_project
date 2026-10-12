import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/auth_provider.dart';

Future<void> showAdminLoginDialog(BuildContext context) async {
  await context.read<AuthProvider>().initialize();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _AdminLoginDialog(),
  );
}

class _AdminLoginDialog extends StatefulWidget {
  const _AdminLoginDialog();

  @override
  State<_AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<_AdminLoginDialog> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirmation = TextEditingController();
  final _bootstrapToken = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _pinConfirmation.dispose();
    _bootstrapToken.dispose();
    super.dispose();
  }

  void _onKeyPress(String val) {
    if (_pin.text.length < 6) {
      setState(() {
        _pin.text += val;
        _validationError = null;
      });
    }
  }

  void _onBackspace() {
    if (_pin.text.isNotEmpty) {
      setState(() {
        _pin.text = _pin.text.substring(0, _pin.text.length - 1);
        _validationError = null;
      });
    }
  }

  void _onClear() {
    setState(() {
      _pin.text = '';
      _validationError = null;
    });
  }

  Future<void> _submit(AuthProvider auth) async {
    if (!RegExp(r'^\d{6}$').hasMatch(_pin.text)) {
      setState(() => _validationError = 'PIN harus terdiri dari 6 angka.');
      return;
    }
    if (auth.needsPinSetup && _pin.text != _pinConfirmation.text) {
      setState(() => _validationError = 'Konfirmasi PIN tidak cocok.');
      return;
    }
    if (auth.needsPinSetup &&
        (_name.text.trim().isEmpty || _bootstrapToken.text.trim().isEmpty)) {
      setState(
          () => _validationError = 'Nama dan token bootstrap wajib diisi.');
      return;
    }
    if (auth.needsPinSetup && !auth.bootstrapAvailable) {
      setState(() =>
          _validationError = 'Bootstrap PIN belum dikonfigurasi di server.');
      return;
    }
    setState(() => _validationError = null);
    final success = auth.needsPinSetup
        ? await auth.setupAdminWithPin(
            _name.text.trim(), _pin.text, _bootstrapToken.text.trim())
        : await auth.loginWithPin(_pin.text, expectedRole: 'ADMIN');
    if (success && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    const terracotta = Color(0xFFC45A34);
    const darkBrown = Color(0xFF3B2820);
    const mutedGray = Color(0xFF8C7D73);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon & Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 32),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5EBE1),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFEADBCE)),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: terracotta,
                      size: 26,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: mutedGray),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                auth.needsPinSetup ? 'Siapkan PIN Admin' : 'Masuk Area Admin',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: darkBrown,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                auth.needsPinSetup
                    ? 'Buat PIN 6-digit untuk keamanan akun admin'
                    : 'Masukkan 6-digit PIN keamanan Anda',
                textAlign: TextAlign.center,
                style: const TextStyle(color: mutedGray, fontSize: 12),
              ),
              const SizedBox(height: 20),

              // PIN Indicator Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final isFilled = index < _pin.text.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? terracotta : const Color(0xFFE2E8F0),
                      boxShadow: isFilled
                          ? [
                              BoxShadow(
                                color: terracotta.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),

              if (auth.needsPinSetup) ...[
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: 'Nama Admin',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bootstrapToken,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Token Bootstrap Server',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinConfirmation,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Ulangi PIN Admin',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Validation / Auth Error Banner
              if (_validationError != null || auth.error != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCE8E6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _validationError ?? auth.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFD93025),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Numpad Keypad (1 to 9, C, 0, Backspace)
              if (!auth.needsPinSetup) ...[
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  childAspectRatio: 1.6,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    ...['1', '2', '3', '4', '5', '6', '7', '8', '9'].map(
                      (number) => Material(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () => _onKeyPress(number),
                          borderRadius: BorderRadius.circular(14),
                          child: Center(
                            child: Text(
                              number,
                              style: const TextStyle(
                                color: darkBrown,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Material(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: _onClear,
                        borderRadius: BorderRadius.circular(14),
                        child: const Center(
                          child: Text(
                            'C',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Material(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => _onKeyPress('0'),
                        borderRadius: BorderRadius.circular(14),
                        child: const Center(
                          child: Text(
                            '0',
                            style: TextStyle(
                              color: darkBrown,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Material(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: _onBackspace,
                        borderRadius: BorderRadius.circular(14),
                        child: const Center(
                          child: Icon(
                            Icons.backspace_outlined,
                            size: 18,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: auth.isLoading ? null : () => _submit(auth),
                  style: FilledButton.styleFrom(
                    backgroundColor: terracotta,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: auth.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          auth.needsPinSetup ? 'Siapkan PIN' : 'Masuk Area Admin',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
