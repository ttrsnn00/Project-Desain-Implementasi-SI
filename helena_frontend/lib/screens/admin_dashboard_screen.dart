import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../config/api_config.dart';
import '../utils/token_storage.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart'; // dipakai untuk reuse CurrencyFormatId

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _mahasiswaList = [];
  // nim -> data tagihan (kalau sudah ada). Kalau NIM tidak ada di sini,
  // berarti mahasiswa itu BELUM punya tagihan UKT sama sekali.
  Map<String, dynamic> _tagihanByNim = {};

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  // Data mahasiswa (auth-service) dan data tagihan (campus-billing-service)
  // ada di database TERPISAH (prinsip isolasi data antar microservice) --
  // jadi harus diambil lewat dua panggilan API berbeda, lalu digabung di sini.
  Future<void> _muatData() async {
    setState(() => _isLoading = true);

    final token = await TokenStorage.getToken();
    if (token == null) {
      _kembaliKeLogin();
      return;
    }

    try {
      final mahasiswaResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/auth-protected/users'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (mahasiswaResponse.statusCode == 401 || mahasiswaResponse.statusCode == 403) {
        _kembaliKeLogin();
        return;
      }

      final mahasiswaJson = jsonDecode(mahasiswaResponse.body);
      if (mahasiswaJson['status'] != 'success') {
        _tampilkanPesan(mahasiswaJson['message'] ?? 'Gagal memuat daftar mahasiswa.', isError: true);
        setState(() => _isLoading = false);
        return;
      }

      final List<Map<String, dynamic>> mahasiswaList =
          List<Map<String, dynamic>>.from(mahasiswaJson['data']);

      // Untuk tiap mahasiswa, cek apakah sudah punya tagihan.
      // (Sengaja satu-satu, bukan endpoint gabungan -- karena memang
      // belum ada endpoint "daftar semua tagihan" di backend. Untuk jumlah
      // mahasiswa kecil ini cukup; kalau datanya besar, sebaiknya nanti
      // dibuatkan endpoint khusus di backend yang query lebih efisien.)
      final Map<String, dynamic> tagihanMap = {};
      for (final mhs in mahasiswaList) {
        final nim = mhs['nim'];
        final tagihanResponse = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/kampus/tagihan/$nim'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (tagihanResponse.statusCode == 200) {
          final tagihanJson = jsonDecode(tagihanResponse.body);
          if (tagihanJson['status'] == 'success' && tagihanJson['data'] != null) {
            tagihanMap[nim] = tagihanJson['data'];
          }
        }
      }

      if (mounted) {
        setState(() {
          _mahasiswaList = mahasiswaList;
          _tagihanByNim = tagihanMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error memuat data admin: $e');
      if (mounted) {
        _tampilkanPesan('Gagal terhubung ke server.', isError: true);
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _terbitkanTagihan(String nim, int nominal) async {
    final token = await TokenStorage.getToken();
    if (token == null) {
      _kembaliKeLogin();
      return;
    }

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
        if (mounted) {
          _tampilkanPesan('Tagihan UKT untuk $nim berhasil diterbitkan!');
        }
        await _muatData(); // refresh daftar supaya status terbaru kelihatan
      } else {
        if (mounted) {
          _tampilkanPesan(jsonResponse['message'] ?? 'Gagal menerbitkan tagihan.', isError: true);
        }
      }
    } catch (e) {
      debugPrint('Error menerbitkan tagihan: $e');
      if (mounted) {
        _tampilkanPesan('Gagal terhubung ke server.', isError: true);
      }
    }
  }

  void _tampilkanFormTagihan(String nim, String nama) {
    final nominalController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terbitkan Tagihan UKT'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mahasiswa: $nama ($nim)', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: nominalController,
              keyboardType: TextInputType.number,
              inputFormatters: [CurrencyFormatId()],
              decoration: const InputDecoration(
                labelText: 'Nominal UKT (Rp)',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              // Hapus titik pemisah ribuan ('500.000' -> '500000') sebelum di-parse,
              // karena field ini sekarang otomatis berformat ribuan saat diketik.
              final teksAngkaSaja = nominalController.text.replaceAll('.', '');
              final nominal = int.tryParse(teksAngkaSaja);
              if (nominal == null || nominal <= 0) {
                _tampilkanPesan('Nominal tidak valid!', isError: true);
                return;
              }
              Navigator.pop(context);
              _terbitkanTagihan(nim, nominal);
            },
            child: const Text('Terbitkan'),
          ),
        ],
      ),
    );
  }

  void _tampilkanPesan(String pesan, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(pesan),
        backgroundColor: isError ? Colors.red : Colors.green,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Dashboard Admin'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muatData,
              child: _mahasiswaList.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 100),
                        Center(child: Text('Belum ada mahasiswa terdaftar.')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _mahasiswaList.length,
                      itemBuilder: (context, index) {
                        final mhs = _mahasiswaList[index];
                        final nim = mhs['nim'];
                        final nama = mhs['nama'];
                        final sudahPunyaTagihan = _tagihanByNim.containsKey(nim);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: CircleAvatar(
                              backgroundColor: sudahPunyaTagihan ? Colors.green[100] : Colors.orange[100],
                              child: Icon(
                                sudahPunyaTagihan ? Icons.check : Icons.priority_high,
                                color: sudahPunyaTagihan ? Colors.green[800] : Colors.orange[800],
                              ),
                            ),
                            title: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              'NIM: $nim\n${sudahPunyaTagihan ? "Sudah punya tagihan UKT" : "Belum punya tagihan UKT"}',
                            ),
                            isThreeLine: true,
                            trailing: sudahPunyaTagihan
                                ? null
                                : ElevatedButton(
                                    onPressed: () => _tampilkanFormTagihan(nim, nama),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue[800],
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Approve'),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
