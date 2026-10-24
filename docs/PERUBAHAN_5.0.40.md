# MusikKu 5.0.40+18 — perbaikan sinkronisasi Dengerin Bareng

- Memperbaiki bug ketika metadata lagu tamu sudah sama dengan host, tetapi player native belum memuat sumber audio. Metadata tersimpan tidak lagi dianggap sebagai bukti bahwa lagu benar-benar dimuat di Media3.
- Memverifikasi ID pada state native serta status sumber audio sebelum melewati langkah pemuatan lagu.
- Menambahkan tes regresi untuk metadata yang cocok tanpa audio native, native player yang masih memegang lagu lain, dan lagu yang sudah termuat dengan benar.
- Menambahkan jeda retry 12 detik untuk kegagalan pemuatan lagu yang sama agar heartbeat kamar tidak memanggil resolver audio berulang kali. Lagu host yang baru tetap dicoba segera.

Validasi: source dan versi diperiksa secara statis. `flutter analyze`, `flutter test`, build APK, dan uji dua perangkat harus dilakukan lewat GitHub Actions karena Flutter SDK tidak tersedia di lingkungan pengeditan ini.
