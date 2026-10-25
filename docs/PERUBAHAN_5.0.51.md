# MusikKu 5.0.51+29 — Player layout dan update latar belakang

## Perubahan
- Menempatkan label `SEDANG DIPUTAR` di sumbu tengah layar secara independen dari tombol kiri/kanan.
- Menghapus transformasi gambar yang sebelumnya hanya menggeser cover secara visual tanpa menggeser layout, sehingga judul tidak lagi bertumpuk dengan cover.
- Menambahkan kartu ringkas `SELANJUTNYA` yang menampilkan antrean eksplisit atau menjelaskan bahwa Radio akan memilih lagu terkait; kartu membuka antrean ketika disentuh.
- Menyeimbangkan kelompok kontrol dengan distribusi `spaceBetween` agar ruang tidak menumpuk di satu bagian layar.
- Menambahkan opsi opt-in untuk mengunduh APK rilis yang lolos verifikasi checksum secara diam-diam sesudah pemeriksaan saat startup.
- Unduhan latar belakang tidak membuka installer secara otomatis. APK terverifikasi dapat dipasang dari halaman pembaruan dan Android tetap meminta konfirmasi pengguna.
- Mode unduh diam-diam dan mode buka installer otomatis dibuat saling eksklusif.
- Pembaruan latar belakang boleh berjalan saat Player audio terbuka, tetapi update prompt biasa tidak lagi menutupi pemutaran jika musik mulai diputar ketika pemeriksaan sedang berlangsung.

## Batasan yang diketahui
- Unduhan berjalan di proses aplikasi dan dapat berlanjut ketika aplikasi masih aktif/berada di latar belakang; Android tetap bisa menangguhkannya jika proses aplikasi dihentikan. Ini bukan pembaruan instalasi tanpa interaksi.
- Instalasi APK senyap tidak didukung; Android mengendalikan izin dan konfirmasi pemasangan.
- Flutter SDK tidak tersedia saat paket ini disiapkan. Jalankan `flutter pub get`, `flutter analyze`, dan `flutter test` di GitHub Actions sebelum menerbitkan APK.
