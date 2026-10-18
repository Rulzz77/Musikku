# MusikKu 4.7.8 — Build 51

Source Flutter + Android. Build 49 focuses on playlist organization and safer queue editing.

## Perubahan Build 49
- Menambahkan **Playlist pintar** yang dihitung dari data lokal: Mix Favorit, Baru Diputar, Paling Sering Diputar (saat statistik tersedia), dan Putar Lagi. Daftar dihitung ulang dari favorit, riwayat, katalog lagu yang dikenal, dan statistik pemutaran; tidak membuat salinan data persisten baru.
- Menambahkan layar **Playlist MusikKu** di menu Koleksi. Pengguna dapat membuat, mengganti nama, menghapus playlist, menambahkan beberapa lagu dari favorit/riwayat/daftar yang sedang dimuat, memutar playlist/lagu, menghapus lagu, dan drag-and-drop urutan lagu. Urutan disimpan melalui storage playlist yang sudah ada.
- Menambahkan **Undo** untuk penghapusan satu lagu dari antrean dan pengosongan antrean. Item dipulihkan pada posisi sebelumnya, menolak ID duplikat, dan tidak menghapus item baru yang ditambahkan setelah aksi awal.
- Mempertahankan drag-and-drop antrean yang sudah tersedia, serta menguji pemulihan queue dan urutan playlist.
- Metadata versi: `4.7.5+49`.

## Verifikasi sebelum rilis

Jalankan di lingkungan yang memiliki Flutter SDK dan Android SDK:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Uji perangkat yang disarankan: buka Koleksi → Playlist MusikKu; buat playlist, tambahkan lagu dari menu lagu, ubah urutan, tutup dan buka kembali aplikasi; uji Undo setelah menghapus satu lagu dari antrean; kosongkan antrean lalu Undo; tambahkan lagu baru sebelum Undo dan pastikan tidak hilang; pastikan playlist pintar kosong atau berisi lagu sesuai data yang tersedia.

Laporan terpisah ada pada `CHANGELOG.md`, `FEATURE-AUDIT.md`, `VALIDATION-REPORT.md`, dan `UI-REGRESSION-AUDIT.md`.


## Perbaikan Build 49
- Memperbaiki import ambigu metadata versi di halaman Diagnostik.
- Memperbaiki variabel tema di halaman Playlist MusikKu.
- Menggunakan callback `onReorderItem` yang baru dan menguji ulang perpindahan indeks playlist.


Build 49 adds a manual 5-band EQ interface, centered synced lyrics, and cleanup of a duplicate crossfade UI state update. See CHANGELOG.md and FEATURE-AUDIT.md for limits and validation status.


## Perubahan Build 51
- Pemulihan sesi akun Google secara diam-diam saat aplikasi dibuka kembali.
- Lagu aktif ditandai di playlist MusikKu dan daftar koleksi.
- Notifikasi unggahan/live subscription dihapus; notifikasi kontrol media Android tetap dipakai untuk playback di latar belakang.
- Riwayat pencarian bisa dihapus satu per satu atau sekaligus.
- Metadata versi: `4.7.8+52`.

CI tetap perlu menjalankan `flutter analyze`, `flutter test`, dan `flutter build apk --release`; pemeriksaan tersebut belum tersedia di lingkungan penyusunan ZIP ini.


Build 52 hotfix: explicit import for `ValueListenable` in the custom playlist page.
