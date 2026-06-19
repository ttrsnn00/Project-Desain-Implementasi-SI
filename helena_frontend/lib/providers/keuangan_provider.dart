import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class KeuanganProvider with ChangeNotifier {
  Map<String, dynamic>? tagihan;
  List<dynamic> riwayat = [];
  bool isLoading = true;
  
  int saldoTotal = 0;
  int pemasukanTotal = 0;
  int pengeluaranTotal = 0;
  
  int currentPage = 1;
  bool hasMoreData = true;
  bool isFetchingMore = false;

  Future<void> fetchDataKeuangan(String nim, {bool isBackgroundRefresh = false}) async {
    // --- PERBAIKAN BUG STATE LEAKAGE ---
    // Bersihkan memori setiap kali fungsi dipanggil (kecuali saat refresh di latar belakang)
    if (!isBackgroundRefresh) {
      isLoading = true;
      tagihan = null; 
      riwayat = [];
      saldoTotal = 0;
      pemasukanTotal = 0;
      pengeluaranTotal = 0;
      notifyListeners(); 
    }
    
    currentPage = 1;
    hasMoreData = true;

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};

      // 1. Ambil Tagihan
      final resTagihan = await http.get(Uri.parse('${ApiConfig.baseUrl}/kampus/tagihan/$nim'), headers: headers)
          .timeout(const Duration(seconds: 5));
      
      if (resTagihan.statusCode == 200) {
        final jsonResponse = jsonDecode(resTagihan.body);
        if (jsonResponse['status'] == 'success') {
          tagihan = jsonResponse['data'];
        }
      } else {
        // Jika 404 (Belum ada tagihan), pastikan memori dikosongkan!
        tagihan = null;
      }

      // 2. Ambil Ringkasan Saldo
      final resRingkasan = await http.get(Uri.parse('${ApiConfig.baseUrl}/uang-saku/ringkasan/$nim'), headers: headers)
          .timeout(const Duration(seconds: 5));
      
      if (resRingkasan.statusCode == 200) {
        final jsonResponse = jsonDecode(resRingkasan.body);
        if (jsonResponse['status'] == 'success') {
          final dataRingkasan = jsonResponse['data'];
          saldoTotal = dataRingkasan['saldo'] ?? 0;
          pemasukanTotal = dataRingkasan['pemasukan'] ?? 0;
          pengeluaranTotal = dataRingkasan['pengeluaran'] ?? 0;
        }
      }

      // 3. Ambil Riwayat
      final resRiwayat = await http.get(Uri.parse('${ApiConfig.baseUrl}/uang-saku/riwayat/$nim?page=1&limit=5'), headers: headers)
          .timeout(const Duration(seconds: 5));
          
      if (resRiwayat.statusCode == 200) {
        final jsonResponse = jsonDecode(resRiwayat.body);
        if (jsonResponse['status'] == 'success') {
          final dataBaru = jsonResponse['data'] as List;
          riwayat = dataBaru;
          if (dataBaru.length < 5) hasMoreData = false;
        }
      } else {
        riwayat = [];
      }

    } catch (e) {
      debugPrint("Error Fetch Data: $e");
      tagihan = null;
      riwayat = []; 
    } finally {
      if (!isBackgroundRefresh) {
        isLoading = false; 
      }
      notifyListeners();
    }
  }

  Future<void> fetchMoreData(String nim) async {
    if (isFetchingMore || !hasMoreData) return;

    isFetchingMore = true;
    currentPage++;
    notifyListeners();

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      
      final resRiwayat = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/uang-saku/riwayat/$nim?page=$currentPage&limit=5'), 
        headers: {'Authorization': 'Bearer $token'}
      );

      if (resRiwayat.statusCode == 200) {
        final jsonResponse = jsonDecode(resRiwayat.body);
        if (jsonResponse['status'] == 'success') {
          final dataTambahan = jsonResponse['data'] as List;
          riwayat.addAll(dataTambahan);
          if (dataTambahan.length < 5) hasMoreData = false;
        }
      }
    } catch (e) {
      debugPrint("Error Fetch More: $e");
      currentPage--; 
    } finally {
      isFetchingMore = false;
      notifyListeners();
    }
  }

  Future<bool> hapusTransaksi(int idTransaksi, String nim) async {
    final backupRiwayat = List.from(riwayat); 
    riwayat.removeWhere((item) => item['id'] == idTransaksi);
    notifyListeners();

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/uang-saku/transaksi/$idTransaksi'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['status'] == 'success') {
           await fetchDataKeuangan(nim, isBackgroundRefresh: true); 
           return true;
        }
      }
      riwayat = backupRiwayat;
      notifyListeners();
      return false;
      
    } catch (e) {
      debugPrint("Error Hapus Transaksi: $e");
      riwayat = backupRiwayat;
      notifyListeners();
      return false;
    }
  }

  // --- FUNGSI BAYAR UKT NYATA ---
  Future<bool> bayarUKTReal(String nim, int nominalUKT) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};

      final resBayar = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/kampus/tagihan/$nim/bayar'),
        headers: headers,
      );

      if (resBayar.statusCode == 200) {
        final jsonBayar = jsonDecode(resBayar.body);
        if (jsonBayar['status'] == 'success') {
          
          await http.post(
            Uri.parse('${ApiConfig.baseUrl}/uang-saku/transaksi'),
            headers: headers,
            body: jsonEncode({
              'nim': nim,
              'nominal': nominalUKT,
              'jenis_transaksi': 'pengeluaran',
              'keterangan': 'Pembayaran UKT Kampus',
              'tanggal': DateTime.now().toIso8601String().split('T')[0]
            }),
          );

          await fetchDataKeuangan(nim, isBackgroundRefresh: true);
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint("Error Bayar UKT: $e");
      return false;
    }
  }
}