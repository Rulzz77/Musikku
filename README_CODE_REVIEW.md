# MusikKu v4.8.16+70 — Review

## Tujuan perubahan
Memastikan katalog tampil sebagai katalog musik, bukan feed video umum; memusatkan kontrol pengaturan di halaman Pengaturan MusikKu.

## Perubahan
- Filter Shorts berbasis hashtag/label tetap aktif.
- Menambahkan penyaringan video berdurasi maksimal 3 menit yang tidak memiliki sinyal rilis/performa musik yang kuat; ini mengatasi video pendek non-musik yang salah kategori sebagai Music.
- Mempertahankan metadata deskripsi untuk menyokong klasifikasi musik.
- Menerapkan kebijakan yang sama pada katalog populer, pencarian, radio, unggahan langganan, Mix favorit, riwayat, dan daftar lagu dari playlist/liked.
- Menaikkan versi kunci cache agar hasil lama yang tidak difilter tidak dibaca kembali.
- Menghilangkan shortcut Hemat data dari header setiap tab; akses Pengaturan MusikKu hanya tersisa pada satu kartu di Koleksi. Opsi jaringan/data tetap tersedia di AppSettingsPage.
- Versi: `4.8.16+70`.

## Batas verifikasi
Pemeriksaan teks dan referensi file dapat dilakukan statis. Flutter/Dart SDK tidak tersedia di lingkungan penyusunan paket, sehingga `flutter analyze`, `flutter test`, dan `flutter build apk --debug` belum dijalankan.

## Build 71 — pengurangan request YouTube
- Pencarian lagu tidak lagi otomatis memanggil pencarian channel kedua. Pencarian channel dibuat atas permintaan pengguna dan cache lokalnya bertahan lintas sesi.
- Radio maksimal mengambil tiga halaman `search.list` untuk satu pengisian antrean.
- `YoutubeApiRequestGuard` kini memberi jarak minimal 500 ms per scope dan menyimpan cooldown rate-limit/kuota ke SharedPreferences agar restart aplikasi tidak langsung menembakkan request lagi.
- Ini mengurangi request berulang, tetapi tidak menghapus batas kuota YouTube atau menjamin tidak ada HTTP 429.
