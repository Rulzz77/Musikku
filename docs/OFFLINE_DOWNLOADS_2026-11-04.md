# MusikKu Offline Downloads — 4 November 2026

## Implementasi

- Tidak menambahkan `youtube_explode_dart` untuk proses download.
- Download menggunakan MethodChannel `musikku/newpipe` yang sudah terdaftar di `NewPipeExtractorBridge.resolveAudio(videoId)`.
- Audio disimpan di folder privat aplikasi: `Documents/MusikKu/Offline/`.
- Status dan antrean disimpan ke SharedPreferences; file sementara memakai ekstensi `.part`.
- Antrean diproses satu per satu. Permintaan Range digunakan untuk melanjutkan file parsial ketika server mendukungnya.
- Metadata `offlinePath` disimpan di setiap entry playlist.
- Pemutaran playlist akan memilih file lokal untuk lagu yang sudah diunduh; lagu lainnya tetap diputar online. Tombol `Putar offline` hanya memasukkan file lokal dan hasil unduhan yang benar-benar tersedia.
- Fitur downloader saat ini Android-only karena bridge `musikku/newpipe` hanya terdaftar di Android.

## Izin konten

Fungsi penyimpanan stream hanya boleh diaktifkan untuk konten yang penggunaan, pengunduhan, dan pemutaran offline-nya telah mendapat izin tertulis/lisensi yang sesuai. Pastikan izin yang dimiliki developer MusikKu secara eksplisit mencakup aplikasi, wilayah, jenis konten, serta penyimpanan dan pemutaran offline.

## Catatan teknis

- Resume memakai HTTP `Range` dan meminta URL stream baru dari bridge agar signed URL yang kedaluwarsa tidak disimpan.
- File akhir diputar lewat jalur local Media3 yang sudah ada (`loadLocal`).
- Belum tersedia background/foreground download service native; unduhan berjalan selama proses MusikKu tetap hidup.
- iOS belum didukung karena jalur playback iOS memakai YouTube iFrame, bukan resolver Android NewPipe.
