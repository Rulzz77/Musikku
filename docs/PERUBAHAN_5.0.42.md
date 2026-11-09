# MusikKu 5.0.42+20

- Menyertakan snapshot playback terakhir di heartbeat host untuk recovery ketika broadcast `music_state` terlewat.
- Guest mengonsumsi snapshot dari heartbeat host dengan validasi kode kamar dan jenis state.
- Jika heartbeat host datang tetapi belum menyertakan snapshot, status diagnostik berubah dari permintaan tanpa akhir menjadi menunggu snapshot.
- Menambah tes untuk pemulihan snapshot melalui heartbeat.
- Menyamakan metadata versi aplikasi ke 5.0.42+20.

Pemeriksaan Flutter langsung tetap perlu dijalankan melalui GitHub Actions (`flutter analyze` dan `flutter test`) sebelum APK diuji di dua perangkat.
