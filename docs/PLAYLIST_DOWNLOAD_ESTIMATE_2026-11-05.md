# Estimasi ukuran Download Semua Playlist

## Perubahan

- Sebelum lagu playlist dimasukkan ke antrean, MusikKu menampilkan dialog konfirmasi.
- Dialog menampilkan jumlah lagu, lagu yang sudah ada di antrean, ukuran yang sudah diketahui, estimasi MB, dan lagu tanpa informasi durasi/ukuran.
- Jika item unduhan sudah memiliki `totalBytes` dari respons sebelumnya/unduhan aktif, nilai tersebut digunakan sebagai ukuran yang diketahui.
- Lagu lainnya dihitung lokal dari durasi dengan bitrate nominal 128 kbps dan rentang kasar 96–192 kbps.
- Lagu lokal, file offline yang benar-benar masih ada, dan ID lagu duplikat tidak dihitung ulang.
- Path offline yang sudah tidak ada tidak lagi dianggap sebagai file offline yang valid.
- `enqueueAll` mengembalikan ringkasan: ditambahkan, sudah antre, sudah offline, dan gagal. SnackBar menampilkan jumlah aktual, bukan mengklaim semua berhasil.

## Batas akurasi

Estimasi durasi dihitung dengan:

`bytes = durationSeconds × bitrateKbps × 1000 ÷ 8`

Ini perkiraan, bukan ukuran file yang dijamin. Ukuran aktual dapat berubah karena bitrate, codec/container, dan metadata. Lagu yang tidak memiliki durasi dan ukuran aktual tidak masuk ke estimasi.

## Izin konten

Estimasi ini tidak memeriksa atau memberikan hak untuk mengunduh. Fitur unduhan hanya boleh digunakan untuk sumber audio yang memang memberi izin/lisensi pengunduhan, penyimpanan lokal, dan pemutaran offline.

## Pengujian yang ditambahkan

`test/audio_download_estimator_test.dart` menguji perhitungan 128 kbps, rentang 96–192 kbps, durasi tidak tersedia/tidak valid, penjumlahan beberapa lagu, dan prioritas ukuran yang sudah diketahui.
