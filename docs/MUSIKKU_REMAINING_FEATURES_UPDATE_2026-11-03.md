# MusikKu — Remaining Features Update

Pembaruan ini melengkapi sejumlah fitur yang sebelumnya masih tercatat sebagai belum tersedia pada Feature Pack. Implementasi ini mempertahankan mesin pemutaran dan menyentuh lapisan pencarian, lirik, penyimpanan artwork, backup, serta interaksi Listening Together.

## Implementasi dalam pembaruan ini

### 1. Advanced Music Search
- Filter jenis konten: semua, Official Audio, Music Video, dan Live Performance.
- Filter durasi: di bawah 4 menit, 4–20 menit, dan di atas 20 menit.
- Urutan: relevansi, terbaru, dan paling banyak ditonton.
- Pilihan bahasa Indonesia/Inggris sebagai petunjuk query pencarian.
- Filter durasi/jenis konten dan pengurutan diterapkan lagi secara lokal pada hasil yang diterima.
- Catatan: label Official Audio/Music Video/Live adalah heuristik dari judul, deskripsi, dan channel, bukan verifikasi resmi YouTube. Pilihan bahasa menambahkan petunjuk ke query; bahasa lagu tidak selalu dapat dipastikan dari metadata.

### 2. Advanced Lyrics
- Pengaturan offset sinkronisasi manual per video (±8 detik).
- Ukuran teks lirik 15–32 px yang disimpan secara lokal.
- Ketukan baris lirik tetap melakukan seek dengan memperhitungkan offset.
- Catatan: ketersediaan sinkronisasi otomatis tetap bergantung pada sumber lirik yang ditemukan. Pengaturan offset tidak membuat lirik yang tidak tersedia menjadi tersedia.

### 3. Backup dan restore lokal
- JSON backup mencakup favorit, playlist, antrean, riwayat, statistik dengar, progres, beberapa pengaturan, daftar artis favorit, daftar lagu yang disembunyikan dari Flow, Radio Diary, dan metadata artwork custom.
- File cover custom ikut disematkan sebagai Base64 dengan batas 3 MB per gambar dan 12 MB total agar backup tidak membengkak tanpa batas. File yang melebihi batas tersebut dilewati.
- Pemulihan membuat file artwork pada folder dokumen aplikasi dan memetakan ulang ID lagu ke path baru.
- Backup lama yang hanya menyimpan path artwork tetap didukung untuk path yang masih valid pada perangkat yang sama.
- Catatan: ekspor membuat file JSON pada direktori dokumen aplikasi. JSON disalin ke clipboard bila ukurannya tidak lebih dari sekitar 2 MB; untuk backup besar gunakan file JSON yang tersimpan. Pemulihan dari clipboard memerlukan isi JSON.

### 4. Custom artwork per lagu
- Pilih **Ganti cover lagu** dari menu opsi lagu untuk mengambil gambar dari galeri.
- Artwork disimpan pada direktori dokumen aplikasi dan diprioritaskan pada tampilan cover di player dan daftar lagu.
- **Pulihkan cover asli** menghapus override.
- Artwork custom ikut backup jika ukuran gambar masih dalam batas ekspor yang disebutkan di atas.

### 5. MusikKu Party di Listening Together
- Reaksi emoji realtime untuk peserta yang sedang online.
- Host dapat membuat polling dengan 2–4 opsi; penerima menolak event polling yang bukan berasal dari identitas host ruang.
- Peserta online dapat memilih opsi; satu client ID memiliki satu suara aktif dan dapat mengubah pilihannya.
- Catatan: reaksi dan polling menggunakan Supabase Realtime Broadcast. Event bersifat sementara, bukan arsip database; peserta yang baru masuk setelah polling dibuat mungkin tidak menerima polling sebelumnya. Ini bukan sistem voting yang diautentikasi untuk transaksi sensitif. Kode kamar harus dibagikan hanya ke orang yang diundang.

## Fitur sebelumnya yang tetap dipakai

MusikKu Studio (Music DNA, Flow, Memories, Focus Timer, Car Mode), pilihan tema, pengelolaan playlist, Smart Shuffle/Radio yang telah ada, penyimpanan antrean, Crossfade fade-out, Sleep Timer, equalizer best-effort, Data Saver, media notification/lock-screen, serta Listening Together.

## Batas teknis yang masih belum dipenuhi

- **Visualizer PCM real-time:** player YouTube berbasis iframe tidak memberikan PCM ke aplikasi. Visualizer dari sumber tersebut belum diimplementasikan.
- **Gapless playback sejati dan loudness normalization:** tidak dapat dijamin untuk sumber iframe YouTube.
- **Floating Lyrics overlay:** perlu izin overlay dan service native Android tersendiri; belum termasuk dalam paket ini.
- **Home Screen Widget / Android Auto:** memerlukan integrasi native Android dan/atau iOS tambahan; belum termasuk dalam paket ini.
- **Bluetooth auto-resume dan pemilihan output lanjutan:** bergantung pada routing audio/native lifecycle yang harus diuji pada perangkat nyata; belum diklaim selesai.
- **Party persistence:** event reaksi/poll belum disimpan di database; data hanya tersedia selama peserta terhubung dan menerima broadcast.

## Validasi yang dilakukan

Pemeriksaan lokal dilakukan pada 96 file Dart untuk delimiter/string dan import/part relatif, serta parsing `pubspec.yaml`, `analysis_options.yaml`, dan Android XML. Lingkungan pembuatan tidak menyediakan Flutter/Dart SDK, sehingga `flutter analyze`, test suite, dan build APK belum dijalankan. Jalankan semua perintah tersebut pada komputer pengembangan sebelum rilis.

### 6. Recently Added untuk Musik Lokal
- Native Android `MediaStore.Audio.Media.DATE_ADDED` dibaca melalui method channel.
- Metadata tanggal ditambahkan diteruskan ke model `LocalSong`.
- Halaman Musik Lokal memiliki opsi urut **Baru ditambahkan** dan menampilkan tanggal untuk file yang memiliki metadata tersebut.
- Pada perangkat/berkas yang metadata tanggalnya tidak tersedia, nilai `0` diperlakukan sebagai data tidak diketahui.

### 7. Pengujian filter pencarian
- Ditambahkan `test/youtube_search_filters_test.dart` untuk menguji filter durasi, sinyal kanal Official Audio, urutan jumlah tayangan, petunjuk query bahasa/jenis konten, dan perilaku urutan default.
- Tes belum dieksekusi karena Flutter SDK tidak tersedia di lingkungan pembuatan paket.
