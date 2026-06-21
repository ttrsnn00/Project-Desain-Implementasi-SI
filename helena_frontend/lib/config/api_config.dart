class ApiConfig {
  // Pakai localhost + 'adb reverse tcp:4000 tcp:4000' (lihat catatan di README/chat),
  // bukan IP WiFi. Caranya: HP terhubung USB, port 4000 di HP diteruskan ke
  // port 4000 di laptop lewat kabel -- tidak bergantung jaringan WiFi sama sekali,
  // jadi tetap jalan walau ganti WiFi atau WiFi tidak stabil.
  //
  // KONSEKUENSI: setiap kali HP dicabut/disambung ulang USB, atau laptop di-restart,
  // perintah 'adb reverse tcp:4000 tcp:4000' harus dijalankan ULANG dulu sebelum
  // buka aplikasi -- kalau lupa, aplikasi akan gagal connect lagi.
  static const String baseUrl = 'http://localhost:4000';
}