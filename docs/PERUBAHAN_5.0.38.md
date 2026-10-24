# MusikKu 5.0.38+16 — perbaikan Player dan Dengerin Bareng

- Player HP memakai panel kontrol dengan tinggi terikat dan ruang fleksibel sebelum toolbar, sehingga kontrol turun mendekati bagian bawah layar tanpa mengubah rumus ukuran cover.
- Dengerin Bareng menggunakan Supabase Realtime lintas jaringan dan kode kamar 8 digit; tidak ada fallback alamat IP/LAN.
- Host dan tamu dapat mengirim play/pause, pemilihan lagu dari hasil pencarian, stop, Next/Previous, seek, shuffle, smart shuffle, dan repeat melalui host.
- Pesan broadcast Supabase dinormalisasi agar payload yang dibungkus tetap terbaca.
- Kegagalan kirim realtime ditangani melalui alur async yang aman; status setelah Next/Previous/Stop langsung disiarkan kembali, bukan menunggu snapshot 2 detik.
- Tombol Dengerin Bareng ditempatkan pertama di shortcut Beranda.
- Build APK harus menyertakan `SUPABASE_URL` dan `SUPABASE_PUBLISHABLE_KEY` sebagai GitHub Actions Variables. Tanpa itu, fitur online akan menampilkan pesan konfigurasi dan tidak akan terhubung.

Validasi saat paket disiapkan: pemeriksaan statis versi, struktur konfigurasi, jalur import lokal, dan integritas arsip. Flutter SDK tidak tersedia pada lingkungan penyuntingan ini; `flutter analyze`, `flutter test`, build APK, dan uji dua perangkat masih harus dijalankan melalui GitHub Actions/perangkat.
