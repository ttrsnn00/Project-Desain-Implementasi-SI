import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../utils/token_storage.dart';

class KeuanganProvider with ChangeNotifier {
  Map<String, dynamic>? tagihan;
  List<dynamic> riwayat = [];
  bool isLoading = true;

  int saldoTotal = 0;
  int pemasukanTotal = 0;
  int pengeluaranTotal = 0;

  // Status per-service: supaya UI bisa kasih info yang tepat
  bool isTagihanAvailable = true;
  bool isPocketMoneyAvailable = true;

  int currentPage = 1;
  bool hasMoreData = true;
  bool isFetchingMore = false;

  Future<void> fetchDataKeuangan(String nim, {bool isBackgroundRefresh = false}) async {
    if (!isBackgroundRefresh) {
      isLoading = true;
      tagihan = null;
      riwayat = [];
      saldoTotal = 0;
      pemasukanTotal = 0;
      pengeluaranTotal = 0;
      isTagihanAvailable = true;
      isPocketMoneyAvailable = true;
      notifyListeners();
    }

    currentPage = 1;
    hasMoreData = true;

    String? token = await TokenStorage.getToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };

    // ── KUNCI FIX ──
    // Setiap request dibungkus try-catch SENDIRI.
    // Kalau satu service mati → hanya data milik service itu yang kosong.
    // Service lain tetap jalan normal. Tidak ada "satu gagal semua ikut crash".

    // 1. Ambil Tagihan (campus-billing-service)
    try {
      final resTagihan = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/kampus/tagihan/$nim'), headers: headers)
          .timeout(const Duration(seconds: 5));

      if (resTagihan.statusCode == 200) {
        final json = jsonDecode(resTagihan.body);
        if (json['status'] == 'success') {
          tagihan = json['data'];
        }
      } else {
        tagihan = null; // 404 = belum ada tagihan, bukan error
      }
      isTagihanAvailable = true;
    } catch (e) {
      // campus-billing-service mati atau timeout
      debugPrint('[Provider] Tagihan fetch gagal: $e');
      tagihan = null;
      isTagihanAvailable = false;
    }

    // 2. Ambil Ringkasan Saldo (pocket-money-service)
    // Try-catch TERPISAH — kalau ini gagal, tagihan di atas sudah aman tersimpan
    try {
      final resRingkasan = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/uang-saku/ringkasan/$nim'), headers: headers)
          .timeout(const Duration(seconds: 5));

      if (resRingkasan.statusCode == 200) {
        final json = jsonDecode(resRingkasan.body);
        if (json['status'] == 'success') {
          final data = json['data'];
          saldoTotal = data['saldo'] ?? 0;
          pemasukanTotal = data['pemasukan'] ?? 0;
          pengeluaranTotal = data['pengeluaran'] ?? 0;
        }
      }
      isPocketMoneyAvailable = true;
    } catch (e) {
      // pocket-money-service mati atau timeout
      debugPrint('[Provider] Ringkasan saldo fetch gagal: $e');
      saldoTotal = 0;
      pemasukanTotal = 0;
      pengeluaranTotal = 0;
      isPocketMoneyAvailable = false;
    }

    // 3. Ambil Riwayat Transaksi (pocket-money-service)
    // Juga terpisah — kalau ringkasan di atas sudah gagal (isPocketMoneyAvailable = false),
    // skip langsung supaya tidak buang waktu timeout lagi
    if (isPocketMoneyAvailable) {
      try {
        final resRiwayat = await http
            .get(
              Uri.parse('${ApiConfig.baseUrl}/uang-saku/riwayat/$nim?page=1&limit=5'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 5));

        if (resRiwayat.statusCode == 200) {
          final json = jsonDecode(resRiwayat.body);
          if (json['status'] == 'success') {
            final dataBaru = json['data'] as List;
            riwayat = dataBaru;
            if (dataBaru.length < 5) hasMoreData = false;
          }
        } else {
          riwayat = [];
        }
      } catch (e) {
        debugPrint('[Provider] Riwayat fetch gagal: $e');
        riwayat = [];
      }
    } else {
      // pocket-money-service sudah konfirmasi mati dari step 2, skip
      riwayat = [];
    }

    if (!isBackgroundRefresh) {
      isLoading = false;
    }
    notifyListeners();
  }

  Future<void> fetchMoreData(String nim) async {
    if (isFetchingMore || !hasMoreData || !isPocketMoneyAvailable) return;

    isFetchingMore = true;
    currentPage++;
    notifyListeners();

    try {
      String? token = await TokenStorage.getToken();

      final resRiwayat = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/uang-saku/riwayat/$nim?page=$currentPage&limit=5'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resRiwayat.statusCode == 200) {
        final json = jsonDecode(resRiwayat.body);
        if (json['status'] == 'success') {
          final dataTambahan = json['data'] as List;
          riwayat.addAll(dataTambahan);
          if (dataTambahan.length < 5) hasMoreData = false;
        }
      }
    } catch (e) {
      debugPrint('Error Fetch More: $e');
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
      String? token = await TokenStorage.getToken();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/uang-saku/transaksi/$idTransaksi'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['status'] == 'success') {
          await fetchDataKeuangan(nim, isBackgroundRefresh: true);
          return true;
        }
      }
      riwayat = backupRiwayat;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('Error Hapus Transaksi: $e');
      riwayat = backupRiwayat;
      notifyListeners();
      return false;
    }
  }

  Future<bool> bayarUKTReal(String nim, int nominalUKT) async {
    try {
      String? token = await TokenStorage.getToken();
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      final resBayar = await http
          .put(
            Uri.parse('${ApiConfig.baseUrl}/kampus/tagihan/$nim/bayar'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 20));

      if (resBayar.statusCode == 200) {
        final json = jsonDecode(resBayar.body);
        if (json['status'] == 'success') {
          await fetchDataKeuangan(nim, isBackgroundRefresh: true);
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error Bayar UKT: $e');
      return false;
    }
  }
}
