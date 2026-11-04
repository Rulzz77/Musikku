# Playlist Offline – 4 November 2026

## Cara kerja

- Playlist (nama, urutan, metadata lagu, dan cover) disimpan lokal melalui `StorageService` / SharedPreferences.
- Lagu online yang sudah ada di playlist dapat diunduh satu per satu melalui ikon download di samping lagu, atau sekaligus melalui **Download semua lagu**. Menambahkan lagu ke playlist tidak otomatis mengunduhnya.
- Downloader Android memakai resolver NewPipe yang sudah ada (`musikku/newpipe` → `resolveAudio(videoId)`), lalu menyimpan file di `Documents/MusikKu/Offline/`. Tidak ada pemakaian `youtube_explode_dart` di proses download.
- Antrean diproses satu per satu. Ada progres, jeda/lanjut, pemulihan file parsial dengan HTTP Range bila server mendukung, retry untuk unduhan gagal, dan penghapusan file. Status antrean disimpan di SharedPreferences.
- Path file offline disimpan sebagai `offlinePath` pada metadata lagu di playlist. File final diputar lewat jalur local Media3 yang sudah ada (`loadLocal`).
- Saat lagu playlist sudah memiliki salinan offline, pemutaran playlist biasa akan memilih file lokal tersebut. Tombol **Putar offline** hanya memutar lagu lokal/unduhan yang file-nya tersedia; lagu yang belum diunduh dilewati.
- Lagu lokal yang sebelumnya dipindai dari perangkat tetap dihitung sebagai tersedia offline.

## Izin konten

Fungsi penyimpanan stream hanya boleh digunakan untuk konten yang penggunaan, pengunduhan, dan pemutaran offline-nya telah mendapat izin tertulis/lisensi yang sesuai. Pastikan izin yang dimiliki developer MusikKu secara eksplisit mencakup aplikasi, wilayah, jenis konten, serta penyimpanan dan pemutaran offline.

## Batasan teknis

- Fitur downloader saat ini Android-only karena bridge `musikku/newpipe` hanya terdaftar di Android. iOS masih menggunakan iFrame YouTube.
- Unduhan berlangsung selama proses MusikKu tetap hidup; belum ditambahkan foreground download service native untuk memastikan unduhan berlanjut setelah Android menutup proses aplikasi.
- URL signed stream hanya dipakai saat download berlangsung dan tidak disimpan ke SharedPreferences.
