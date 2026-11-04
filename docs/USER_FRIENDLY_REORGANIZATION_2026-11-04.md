# MusikKu – User-Friendly Navigation Update (4 November 2026)

## Tujuan
Membuat alur aplikasi lebih mudah dipahami pengguna baru dan mengurangi pintasan/fitur yang tersebar di beberapa halaman.

## Perubahan

### Beranda
- Header diringkas menjadi identitas MusikKu, tombol Pengaturan, judul ajakan, dan satu area pencarian.
- Pengaturan dapat dibuka dari pojok kanan atas.
- Pintasan beranda dibatasi pada Mix untukmu (jika tersedia) dan Dengar bareng.
- Pintasan Lirik, Radio, Musik lokal, dan Riwayat tidak ditampilkan lagi di Beranda karena sudah memiliki tempat yang lebih jelas.
- Kartu sorotan lagu yang menampilkan ulang lagu pertama feed dihapus agar tidak menggandakan konten.
- Pengguna baru melihat panduan singkat: cari lagu, putar lagu, lalu simpan sebagai favorit.
- Filter di Beranda disederhanakan menjadi Semua, Populer, dan Terbaru.

### Jelajah
- Kategori genre tetap berada di satu tempat, yaitu tab Jelajah.
- Tombol Pengaturan tersedia di header tab.

### Koleksi
- Fokus pada Playlist saya, Favorit, Riwayat dengar, Musik di perangkat, dan Statistik.
- Radio tidak diduplikasi di Koleksi karena sudah menjadi tab utama.
- Fitur lanjutan dipusatkan pada satu pintasan Fitur tambahan.
- Pengaturan tidak lagi menjadi baris duplikat di Koleksi; akses Pengaturan tersedia melalui ikon gear di header Beranda dan tab lain.

### Pengaturan dan Fitur tambahan
- Halaman Pengaturan hanya berisi pengaturan aplikasi; pintasan ke MusikKu Studio dihapus.
- MusikKu Studio diakses dari satu tempat, yaitu Koleksi > Fitur tambahan.
- Lirik, Listening Together, pemilihan perangkat audio, dan pilihan tema tidak lagi diduplikasi dalam daftar alat MusikKu Studio; masing-masing tetap tersedia di area pemutar, Beranda, atau Pengaturan.

## Batas verifikasi
Perubahan sumber telah diperiksa secara statis untuk pemanggilan constructor dan rujukan metode. Flutter SDK tidak tersedia pada lingkungan penyuntingan ini, sehingga `flutter analyze`, widget test, dan build APK belum dijalankan.
