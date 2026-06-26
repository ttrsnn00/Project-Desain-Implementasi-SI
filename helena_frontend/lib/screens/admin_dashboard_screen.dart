import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import '../config/api_config.dart';
import '../utils/token_storage.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _mahasiswaList = [];
  Map<String, dynamic> _tagihanByNim = {};

  int get _totalMahasiswa => _mahasiswaList.length;
  int get _sudahTagihan => _tagihanByNim.length;
  int get _belumTagihan => _totalMahasiswa - _sudahTagihan;
  int get _totalLunas =>
      _tagihanByNim.values.where((t) => t['status'] == 'Lunas').length;
  int get _totalPendapatan => _tagihanByNim.values
      .where((t) => t['status'] == 'Lunas')
      .fold(0, (sum, t) => sum + (t['ukt_total'] as int));

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  Future<void> _muatData() async {
    setState(() => _isLoading = true);
    final token = await TokenStorage.getToken();
    if (token == null) { _kembaliKeLogin(); return; }

    try {
      final mahasiswaResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/auth-protected/users'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (mahasiswaResponse.statusCode == 401 ||
          mahasiswaResponse.statusCode == 403) {
        _kembaliKeLogin();
        return;
      }

      final mahasiswaJson = jsonDecode(mahasiswaResponse.body);
      if (mahasiswaJson['status'] != 'success') {
        _tampilkanPesan(mahasiswaJson['message'] ?? 'Gagal memuat data.', isError: true);
        setState(() => _isLoading = false);
        return;
      }

      final List<Map<String, dynamic>> mahasiswaList =
          List<Map<String, dynamic>>.from(mahasiswaJson['data']);

      final Map<String, dynamic> tagihanMap = {};
      for (final mhs in mahasiswaList) {
        final nim = mhs['nim'];
        try {
          final tagihanResponse = await http.get(
            Uri.parse('${ApiConfig.baseUrl}/kampus/tagihan/$nim'),
            headers: {'Authorization': 'Bearer $token'},
          ).timeout(const Duration(seconds: 5));
          if (tagihanResponse.statusCode == 200) {
            final tj = jsonDecode(tagihanResponse.body);
            if (tj['status'] == 'success' && tj['data'] != null) {
              tagihanMap[nim] = tj['data'];
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _mahasiswaList = mahasiswaList;
          _tagihanByNim = tagihanMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        _tampilkanPesan('Gagal terhubung ke server.', isError: true);
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _terbitkanTagihan(String nim, int nominal) async {
    final token = await TokenStorage.getToken();
    if (token == null) { _kembaliKeLogin(); return; }

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/kampus/tagihan'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'nim': nim, 'ukt_total': nominal}),
      );
      final jsonResponse = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) _tampilkanPesan('Tagihan UKT berhasil diterbitkan!');
        await _muatData();
      } else {
        if (mounted)
          _tampilkanPesan(jsonResponse['message'] ?? 'Gagal menerbitkan tagihan.', isError: true);
      }
    } catch (e) {
      if (mounted) _tampilkanPesan('Gagal terhubung ke server.', isError: true);
    }
  }

  void _tampilkanFormTagihan(String nim, String nama,
      {Map<String, dynamic>? existingTagihan}) {
    final nominalController = TextEditingController(
      text: existingTagihan != null
          ? NumberFormat('#,###', 'id_ID').format(existingTagihan['ukt_total'])
          : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              existingTagihan != null ? 'Perbarui Tagihan UKT' : 'Terbitkan Tagihan UKT',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF3B5BDB),
                    child: Text(
                      nama.isNotEmpty ? nama[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nama,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('NIM: $nim',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nominalController,
              keyboardType: TextInputType.number,
              inputFormatters: [CurrencyFormatId()],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Nominal UKT',
                prefixText: 'Rp ',
                prefixStyle: const TextStyle(
                  color: Color(0xFF3B5BDB),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF3B5BDB), width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      final angka = nominalController.text
                          .replaceAll(RegExp(r'[^0-9]'), '');
                      final nominal = int.tryParse(angka);
                      if (nominal == null || nominal <= 0) {
                        _tampilkanPesan('Nominal tidak valid!', isError: true);
                        return;
                      }
                      Navigator.pop(context);
                      _terbitkanTagihan(nim, nominal);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B5BDB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      existingTagihan != null ? 'Perbarui' : 'Terbitkan',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _tampilkanPesan(String pesan, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(pesan),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _kembaliKeLogin() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  Future<void> _logout() async {
    await TokenStorage.deleteToken();
    await TokenStorage.deleteRole();
    _kembaliKeLogin();
  }

  String _formatRupiah(int nominal) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(nominal);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F9),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3B5BDB)))
          : RefreshIndicator(
              onRefresh: _muatData,
              color: const Color(0xFF3B5BDB),
              child: CustomScrollView(
                slivers: [
                  // ── HEADER ──
                  SliverAppBar(
                    expandedHeight: 310,
                    pinned: true,
                    backgroundColor: const Color(0xFF3B5BDB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.logout_rounded),
                        onPressed: _logout,
                        tooltip: 'Logout',
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      collapseMode: CollapseMode.pin,
                      background: _buildHeader(),
                    ),
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(0),
                      child: Container(
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F3F9),
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                      ),
                    ),
                  ),

                  // ── SECTION LABEL ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Row(
                        children: [
                          const Text(
                            'Daftar Mahasiswa',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1F36),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$_totalMahasiswa mahasiswa',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF3B5BDB)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── LIST ──
                  _mahasiswaList.isEmpty
                      ? SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_outline,
                                    size: 64, color: Colors.grey[300]),
                                const SizedBox(height: 12),
                                Text('Belum ada mahasiswa terdaftar.',
                                    style: TextStyle(color: Colors.grey[500])),
                              ],
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) =>
                                  _buildMahasiswaCard(index),
                              childCount: _mahasiswaList.length,
                            ),
                          ),
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F4AC0), Color(0xFF3B5BDB), Color(0xFF5C7CFA)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Dashboard Admin',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Manajemen tagihan UKT mahasiswa',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 13),
              ),
              const SizedBox(height: 14),

              // ── STAT CARDS ROW ──
              Row(
                children: [
                  _buildStatCard(
                    icon: Icons.people_rounded,
                    label: 'Total',
                    value: '$_totalMahasiswa',
                    sub: 'mahasiswa',
                    iconColor: Colors.white,
                    bgColor: Colors.white.withOpacity(0.15),
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    icon: Icons.check_circle_rounded,
                    label: 'Lunas',
                    value: '$_totalLunas',
                    sub: 'mahasiswa',
                    iconColor: const Color(0xFF69DB7C),
                    bgColor: Colors.white.withOpacity(0.12),
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    icon: Icons.pending_rounded,
                    label: 'Belum',
                    value: '${_sudahTagihan - _totalLunas}',
                    sub: 'belum lunas',
                    iconColor: const Color(0xFFFFD43B),
                    bgColor: Colors.white.withOpacity(0.12),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── TOTAL PENDAPATAN BANNER ──
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 10),
                    const Text(
                      'Total UKT Terkumpul',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      _formatRupiah(_totalPendapatan),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildMahasiswaCard(int index) {
    final mhs = _mahasiswaList[index];
    final nim = mhs['nim'] as String;
    final nama = mhs['nama'] as String;
    final tagihan = _tagihanByNim[nim];
    final sudahTagihan = tagihan != null;
    final statusLunas = tagihan?['status'] == 'Lunas';

    // Warna aksen per status
    final Color accentColor = sudahTagihan
        ? (statusLunas ? const Color(0xFF2F9E44) : const Color(0xFF3B5BDB))
        : const Color(0xFFE67700);
    final Color accentLight = sudahTagihan
        ? (statusLunas ? const Color(0xFFD3F9D8) : const Color(0xFFEEF2FF))
        : const Color(0xFFFFF3BF);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── BARIS ATAS: avatar + info + badge ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              children: [
                // Avatar dengan initial + accent ring
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accentLight,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      nama.isNotEmpty ? nama[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Nama & NIM
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nama,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF1A1F36),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'NIM: $nim',
                        style: const TextStyle(
                            color: Color(0xFF8898AA), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: accentColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        sudahTagihan
                            ? (statusLunas ? 'Lunas' : 'Belum Lunas')
                            : 'Belum Ada',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── DIVIDER tipis ──
          Container(height: 1, color: const Color(0xFFF0F2F5)),

          // ── BARIS BAWAH: nominal + tombol ──
          if (sudahTagihan)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  // Nominal UKT
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NOMINAL UKT',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8898AA),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatRupiah(tagihan['ukt_total']),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                        // Progress bar lunas vs total dibayar
                        if (!statusLunas && tagihan['ukt_dibayar'] != null) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: tagihan['ukt_total'] > 0
                                  ? (tagihan['ukt_dibayar'] as int) /
                                      (tagihan['ukt_total'] as int)
                                  : 0,
                              minHeight: 4,
                              backgroundColor: const Color(0xFFE8EAED),
                              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Terbayar: ${_formatRupiah(tagihan['ukt_dibayar'])}',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF8898AA)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Tombol aksi
                  if (!statusLunas)
                    OutlinedButton.icon(
                      onPressed: () => _tampilkanFormTagihan(
                        nim,
                        nama,
                        existingTagihan: tagihan,
                      ),
                      icon: const Icon(Icons.edit_rounded, size: 14),
                      label: const Text('Perbarui'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF3B5BDB),
                        side: const BorderSide(color: Color(0xFFBFC8FF)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD3F9D8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_rounded,
                              size: 14, color: Color(0xFF2F9E44)),
                          SizedBox(width: 4),
                          Text(
                            'Terbayar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2F9E44),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // ── TOMBOL TERBITKAN (jika belum ada tagihan) ──
          if (!sudahTagihan)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _tampilkanFormTagihan(nim, nama),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Terbitkan Tagihan UKT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B5BDB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                    elevation: 0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Formatter rupiah
class CurrencyFormatId extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final numericOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericOnly.isEmpty) return newValue.copyWith(text: '');
    final value = int.parse(numericOnly);
    final formatter =
        NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0);
    final newText = formatter.format(value);
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
