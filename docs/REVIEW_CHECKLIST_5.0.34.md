# Review checklist — MusikKu 5.0.34+12

## Dengerin Bareng
- [x] Normalisasi payload event Supabase untuk format envelope `{ payload: {...} }` dan format map langsung.
- [x] Membetulkan urutan normalisasi dan filter `clientId` pada `room_join_result`.
- [x] Terapkan normalisasi pada `music_state`, `room_join`, `room_heartbeat`, `room_leave`, dan `room_closed`.
- [x] Periksa hasil `sendBroadcastMessage`; status gagal kini muncul sebagai gangguan realtime.
- [x] Guest mengirim ulang `room_join` saat koneksi realtime tersambung lagi setelah terputus sementara.
- [x] Heartbeat menggunakan jalur penanganan error yang sama dengan pesan realtime lain.
- [x] Samakan kode fallback lokal menjadi 8 digit supaya cocok dengan validasi join layanan.
- [x] Tambahkan unit test untuk envelope Supabase dan payload langsung.

## Player
- [x] Hilangkan transisi slide vertikal yang membuat Player terasa bergerak naik/turun saat terbuka.
- [x] Perpendek header 8dp dan rapatkan jarak judul/kontrol.
- [x] Kompensasi anggaran tinggi cover agar ukuran cover tidak ikut membesar saat header diringkas.

## GitHub / versi
- [x] Sinkronkan `pubspec.yaml` dan `lib/app_info.dart` ke 5.0.34+12.
- [x] Perbaiki `test/app_info_test.dart` yang masih mengharapkan versi 5.0.29+7.
- [x] YAML parse dan `tool/sync_app_version.py --check` lolos.
- [x] Pemeriksaan jalur import/part lokal lolos.

## Belum dapat diverifikasi di lingkungan ini
- [ ] `flutter pub get`, `flutter analyze`, `flutter test`, dan APK build — Flutter SDK tidak tersedia.
- [ ] Koneksi Supabase dari dua HP pada jaringan berbeda — membutuhkan Project URL/publishable key milik pemilik project dan perangkat untuk menguji langsung.

Sebelum build lokal atau CI pertama, jalankan `flutter pub get`. `pubspec.lock` di paket ini masih perlu diregenerasi untuk memasukkan dependency Supabase.
