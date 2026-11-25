# MusikKu 5.0.45+23 — rapikan Player, Beranda, dan sinkronisasi kamar

## Player
- Menghapus kartu animasi dekoratif di ruang kosong; tidak ada visualizer palsu yang mengaku membaca beat audio.
- Mengelompokkan tombol aksi, progress/seek, dan kontrol transport secara lebih rapi, sambil mempertahankan ukuran slot cover.
- Memindahkan pintasan Efek audio/Equalizer keluar dari Player ke Pengaturan agar Player lebih bersih; fitur EQ, volume, dan transisi tetap tersedia dari Pengaturan.

## Beranda
- Memperbarui banner pilihan musik menjadi kartu bergradasi yang menampilkan lagu musik yang tersedia, artis/channel, dan aksi Putar/Radio.
- Mengganti grid pintasan vertikal menjadi rail horizontal dengan kartu yang ringkas.
- Menampilkan Dengerin bareng sebagai pintasan prioritas, diikuti Mix kamu, Radio, Musik lokal, dan Riwayat.
- Menggunakan `MusicTitleFormatter.clean` untuk judul yang ditampilkan di kartu video; metadata asli tetap dipakai untuk pencarian dan identifikasi.

## Logika Dengerin Bareng
- Mengirim perintah playback eksplisit `set_playback` (desired state `playing`) dari tamu, bukan perintah toggle yang bisa berbalik akibat pesan duplikat/terlambat.
- Menjadikan `set_playback` bagian dari aksi yang mendapat snapshot host langsung, sehingga pause/resume tidak perlu menunggu heartbeat dua detik sebagai acknowledgement pertama.
- Menyatukan daftar aksi yang butuh snapshot langsung dalam helper yang dapat diuji dan menambahkan regression test.

## Validasi
- Versi `pubspec.yaml`, `lib/app_info.dart`, dan test metadata disinkronkan ke `5.0.45+23`.
- Tes Flutter dan build APK tetap harus dijalankan melalui GitHub Actions karena Flutter/Dart SDK tidak tersedia di lingkungan pengemasan ini.
