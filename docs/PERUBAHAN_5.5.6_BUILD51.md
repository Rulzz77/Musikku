# MusikKu 5.5.6+51 — Spotify importer tanpa input lagu manual

## Perubahan
- Menghapus kolom untuk menempel judul/artis satu per satu dari dialog preview Spotify.
- Importer sekarang hanya membutuhkan satu link playlist.
- Semua track yang benar-benar dikirim oleh embed publik Spotify diproses otomatis, dengan urutan dan duplikat dipertahankan.
- Ringkasan hasil menyebutkan jumlah yang berhasil diimpor dan jumlah track yang tidak cocok.
- Jika embed hanya menyediakan 100 lagu atau jumlah parsial lainnya, UI menjelaskan bahwa sisa lagu tidak dikirim oleh Spotify. MusikKu tidak meminta input manual dan tidak mengklaim playlist sudah lengkap.
- Menghapus parser helper dan regression test yang khusus menangani track tambahan hasil paste manual.
- Build dinaikkan menjadi 5.5.6+51 dan `lib/app_info.dart` disinkronkan.

## Batas teknis
Spotify's public playlist embed may expose only its first 100 entries. Tanpa Spotify-supported authorized pagination, aplikasi tidak dapat mengambil entri yang tidak dikirim oleh halaman publik. Build ini menjaga proses tetap satu-link dan tanpa API key/OAuth; playlist yang lebih besar mungkin diimpor sebagian, dengan peringatan yang jelas.

## Validasi
- `tool/sync_app_version.py --check` harus lolos.
- Pemindaian source memastikan tidak ada lagi supplementary text field/helper yang dipakai importer.
- Jalankan `flutter analyze`, `flutter test`, dan `flutter build apk --release` pada komputer yang memiliki Flutter SDK.
