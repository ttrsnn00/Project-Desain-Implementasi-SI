import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import '../providers/keuangan_provider.dart';
import '../config/api_config.dart';
import 'login_screen.dart';
import 'profile_screen.dart'; 

class DashboardScreen extends StatefulWidget {
  final String nim;
  const DashboardScreen({super.key, required this.nim});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  
  // Controller untuk form tambah transaksi
  final TextEditingController _nominalController = TextEditingController();
  final TextEditingController _keteranganController = TextEditingController();
  String _jenisTransaksi = 'pengeluaran'; // Default pilihan

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KeuanganProvider>().fetchDataKeuangan(widget.nim);
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
        context.read<KeuanganProvider>().fetchMoreData(widget.nim);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nominalController.dispose();
    _keteranganController.dispose();
    super.dispose();
  }

  // --- FUNGSI LOGOUT ---
  Future<void> _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  // --- FUNGSI TAMBAH TRANSAKSI ---
  Future<void> _tambahTransaksi() async {
    String teksKeterangan = _keteranganController.text.trim();
    String teksNominal = _nominalController.text;

    if (teksKeterangan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Keterangan tidak boleh kosong!'), backgroundColor: Colors.orange),
      );
      return; 
    }

    if (teksNominal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Nominal tidak boleh kosong!'), backgroundColor: Colors.orange),
      );
      return; 
    }

    // Membersihkan titik dari format (misal "50.000" jadi "50000")
    String angkaBersih = teksNominal.replaceAll(RegExp(r'[^0-9]'), '');
    int nominalAngka = int.tryParse(angkaBersih) ?? 0;

    if (nominalAngka <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Nominal transaksi harus lebih dari Rp 0!'), backgroundColor: Colors.orange),
      );
      return; 
    }

    Navigator.pop(context);
    
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/uang-saku/transaksi'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'nim': widget.nim,
          'nominal': nominalAngka, 
          'jenis_transaksi': _jenisTransaksi,
          'keterangan': teksKeterangan,
          'tanggal': DateTime.now().toIso8601String().split('T')[0]
        }),
      );

      final jsonResponse = jsonDecode(response.body);

      if (response.statusCode == 201 && jsonResponse['status'] == 'success') {
        HapticFeedback.mediumImpact(); 
        _nominalController.clear();
        _keteranganController.clear();
        
        if(mounted) context.read<KeuanganProvider>().fetchDataKeuangan(widget.nim, isBackgroundRefresh: true);
      } else {
        if(mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(jsonResponse['message'] ?? 'Gagal menyimpan transaksi'), backgroundColor: Colors.red),
           );
        }
      }
    } catch (e) {
      debugPrint(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Koneksi gagal. Pastikan server terhubung.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- UI: FORM POP-UP BOTTOM SHEET ---
  void _tampilkanFormTambah() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Catat Transaksi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Pengeluaran', style: TextStyle(fontSize: 14)),
                          value: 'pengeluaran',
                          groupValue: _jenisTransaksi,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (value) {
                            setModalState(() => _jenisTransaksi = value!);
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Pemasukan', style: TextStyle(fontSize: 14)),
                          value: 'pemasukan',
                          groupValue: _jenisTransaksi,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (value) {
                            setModalState(() => _jenisTransaksi = value!);
                          },
                        ),
                      ),
                    ],
                  ),
                  
                  TextField(
                    controller: _keteranganController,
                    decoration: InputDecoration(
                      labelText: 'Keterangan (Makan, Bensin, dll)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.notes),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // FORM NOMINAL DENGAN AUTO-FORMAT RUPIAH
                  TextField(
                    controller: _nominalController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly, // Hanya boleh masukkan angka
                      CurrencyFormatId(), // Panggil class formatter di bawah
                    ],
                    decoration: InputDecoration(
                      labelText: 'Nominal (Rp)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.monetization_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _tambahTransaksi,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Simpan Transaksi', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          }
        );
      },
    );
  }

  String formatRupiah(int number) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(number);
  }

  @override
  Widget build(BuildContext context) {
    final formatTanggal = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Helena Finance', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.blue[800],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            tooltip: 'Kelola Akun',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProfileScreen(nim: widget.nim)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Keluar',
            onPressed: _logout,
          ),
        ],
      ),
      body: Consumer<KeuanganProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => provider.fetchDataKeuangan(widget.nim),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.blue[800]!, Colors.blue[600]!]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sisa Uang Saku', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 8),
                          Text(formatRupiah(provider.saldoTotal), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Pemasukan', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  Text(formatRupiah(provider.pemasukanTotal), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('Pengeluaran', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  Text(formatRupiah(provider.pengeluaranTotal), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.account_balance, color: Colors.blue[800]),
                                const SizedBox(width: 8),
                                const Text('Tagihan Kampus (UKT)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const Divider(height: 24),
                            
                            if (provider.tagihan == null)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text(
                                    'Belum ada tagihan UKT aktif yang diterbitkan oleh kampus.', 
                                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            else ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total Tagihan:', style: TextStyle(color: Colors.grey)),
                                  Text(
                                    formatRupiah(provider.tagihan!['ukt_total']),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Status Pembayaran:', style: TextStyle(color: Colors.grey)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: provider.tagihan!['status'] == 'Lunas' ? Colors.green[100] : Colors.orange[100],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      provider.tagihan!['status'],
                                      style: TextStyle(
                                        color: provider.tagihan!['status'] == 'Lunas' ? Colors.green[800] : Colors.orange[800],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              if (provider.tagihan!['status'] != 'Lunas')
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      HapticFeedback.heavyImpact(); 
                                      
                                      int nominalTagihan = provider.tagihan!['ukt_total'];

                                      if (provider.saldoTotal < nominalTagihan) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('⚠️ Saldo Uang Saku tidak cukup untuk bayar UKT!'), backgroundColor: Colors.orange),
                                        );
                                        return;
                                      }

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Memproses pembayaran...'), duration: Duration(seconds: 1)),
                                      );

                                      bool sukses = await provider.bayarUKTReal(widget.nim, nominalTagihan);
                                      
                                      if (sukses && mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Pembayaran UKT Berhasil! Saldo terpotong.'), backgroundColor: Colors.green),
                                        );
                                      } else if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Gagal memproses pembayaran ke server!'), backgroundColor: Colors.red),
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue[800],
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: const Text('Bayar UKT Sekarang', style: TextStyle(color: Colors.white)),
                                  ),
                                )
                            ]
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    const Text('Riwayat Transaksi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 12),

                    if (provider.riwayat.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40.0),
                          child: Column(
                            children: [
                              Icon(Icons.receipt_long, size: 80, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text('Dompet masih kosong.', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                              Text('Catat pemasukan atau pengeluaran pertamamu!', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: provider.riwayat.length,
                        itemBuilder: (context, index) {
                          final transaksi = provider.riwayat[index];
                          final isPemasukan = transaksi['jenis_transaksi'] == 'pemasukan';
                          
                          final isTransaksiUKT = transaksi['keterangan'] == 'Pembayaran UKT Kampus';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            elevation: 1,
                            child: Dismissible(
                              key: Key(transaksi['id'].toString()),
                              direction: isTransaksiUKT ? DismissDirection.none : DismissDirection.endToStart,
                              onDismissed: (direction) {
                                HapticFeedback.vibrate(); 
                                provider.hapusTransaksi(transaksi['id'], widget.nim).then((sukses) {
                                  if (sukses && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Transaksi dihapus'), duration: Duration(seconds: 2)),
                                    );
                                  }
                                });
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20.0),
                                decoration: BoxDecoration(color: Colors.red[400], borderRadius: BorderRadius.circular(15)),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(15),
                                onTap: () => HapticFeedback.lightImpact(),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  leading: CircleAvatar(
                                    backgroundColor: isPemasukan ? Colors.green[100] : Colors.red[100],
                                    child: Icon(
                                      isPemasukan ? Icons.arrow_downward : Icons.arrow_upward,
                                      color: isPemasukan ? Colors.green[700] : Colors.red[700],
                                    ),
                                  ),
                                  title: Text(transaksi['keterangan'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                    transaksi['tanggal'] != null ? formatTanggal.format(DateTime.parse(transaksi['tanggal'])) : '-',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                  ),
                                  trailing: Text(
                                    '${isPemasukan ? '+' : '-'} ${formatRupiah(transaksi['nominal'])}',
                                    style: TextStyle(
                                      color: isPemasukan ? Colors.green[700] : Colors.red[700],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                    if (provider.isFetchingMore)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _tampilkanFormTambah,
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// --- KELAS FORMATTER RUPIAH OTOMATIS ---
class CurrencyFormatId extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    
    // Hapus semua karakter selain angka
    String numericOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericOnly.isEmpty) return newValue.copyWith(text: '');
    
    // Parse ke int
    int value = int.parse(numericOnly);
    
    // Format menjadi format ribuan (contoh: 50.000)
    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0);
    String newText = formatter.format(value);
    
    // Kembalikan teks baru dengan posisi kursor di ujung kanan
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}