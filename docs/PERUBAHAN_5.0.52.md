# MusikKu 5.0.52+30 — Perbaikan lint dan versi

## Perubahan
- Memperbaiki lint `unnecessary_underscores` di `lib/pages/home_page.dart` dengan menggunakan wildcard parameter `_` untuk kedua argumen callback progress yang tidak digunakan.
- Menyelaraskan versi `pubspec.yaml`, `lib/app_info.dart`, dan tes metadata versi menjadi `5.0.52+30`.
- Tidak mengubah alur unduhan pembaruan latar belakang atau tata letak Player pada revisi ini.

## Validasi
- Jalankan `flutter pub get`, `flutter analyze`, dan `flutter test` pada GitHub Actions sebelum merilis APK.
- Paket ini disiapkan tanpa Flutter SDK di lingkungan penyuntingan, sehingga hasil analyze/test langsung tidak diklaim.
