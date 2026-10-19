# MusikKu — paket sumber hasil pemeriksaan

## Perubahan yang disertakan

- Mempertahankan patch sebelumnya untuk tombol tambah ke playlist YouTube, tab Langganan musik, pencatatan statistik dengar, dan interval pencatatan trafik Android.
- Memperjelas konversi tipe pada hasil `num.clamp()` yang dipakai sebagai `double` atau `int` di `state_sync.dart`, `data_loading.dart`, `storage_service.dart`, dan `youtube_live_chat_service.dart`.
- Memulihkan `assets/icon/app_icon.png` dari ikon yang sudah ada di `android/app/src/main/res/drawable/app_icon.png`, karena jalur aset ini diwajibkan oleh `pubspec.yaml` tetapi tidak ada di arsip yang diunggah.
- Menambahkan beberapa unit test dasar untuk kebijakan filter katalog musik.
- Membersihkan direktori build/cache Gradle, file backup `.bak`, serta `android/local.properties` yang berisi path khusus komputer dan metadata versi lama.

## Sebelum build

1. Pastikan Flutter stable yang digunakan mendukung constraint Dart pada `pubspec.yaml`.
2. Jalankan `flutter pub get` dari folder ini. `pubspec.lock` tidak disertakan dalam materi yang diunggah, sehingga dependency lock akan dibuat oleh perintah tersebut.
3. Jalankan `flutter analyze` dan `flutter test --reporter expanded`.
4. Uji di perangkat Android: waktu dengar ketika playback normal, pause/resume, seek, akhir lagu, penambahan playlist akun YouTube, jaringan Wi-Fi/seluler, dan feed Shorts.
5. Build rilis memerlukan konfigurasi signing `android/key.properties` dan credential yang dipakai workflow GitHub.

## Batas verifikasi

Flutter/Dart SDK tidak tersedia di lingkungan pemeriksaan ini, dan akses unduh SDK dari lingkungan ini tidak tersedia. Karena itu, paket ini belum dikompilasi atau dijalankan di perangkat. Unit test yang ditambahkan juga belum dijalankan di sini. Perubahan konversi tipe merupakan perbaikan statis yang terlihat dari kontrak API Dart; validasi final tetap harus dilakukan melalui langkah di atas.

Filter subscription membatasi channel pada yang muncul dalam maksimal 30 item feed musik terkini, sehingga channel musik yang tidak muncul pada feed itu bisa tidak terlihat. Deteksi Shorts menggunakan pemeriksaan endpoint jaringan; saat pemeriksaan gagal, kode saat ini memilih untuk menyaring video yang belum dapat diverifikasi, yang dapat menyembunyikan video biasa pada jaringan tertentu. Ini perlu diuji pada jaringan perangkat target.

Penghitung data menggunakan statistik trafik UID aplikasi untuk Wi-Fi + seluler, bukan pembacaan kuota operator atau pemisahan trafik per jaringan.
