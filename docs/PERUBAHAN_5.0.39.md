# MusikKu 5.0.39+17

## Perbaikan
- Mengganti pemeriksaan `if (safeDuration != null)` di map payload kamar dengan null-aware map element (`'durationSeconds': ?safeDuration`).
- Menjaga `durationSeconds` tetap tidak disertakan ketika nilainya null, sekaligus mengikuti lint `use_null_aware_elements`.
- Menyelaraskan versi aplikasi dan tes metadata versi ke 5.0.39+17.

## Validasi
- Pemeriksaan statis source dan konsistensi metadata dilakukan saat paket dibuat.
- Jalankan `flutter analyze` dan `flutter test` pada GitHub Actions untuk validasi dengan Flutter/Dart SDK proyek.
