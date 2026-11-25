# MusikKu 5.0.44+22

## Perbaikan

- Perintah Pause memancarkan intent ke stream state segera, sebelum menunggu respons native, lalu host langsung mengirim snapshot ke tamu. Resume disiarkan setelah status pemutaran native terkonfirmasi; heartbeat dua detik tetap menjadi jalur pemulihan.
- Pada perangkat tamu, pause dikirim ke player native sebelum seek koreksi posisi supaya seek tidak memperlambat perintah berhenti.
- Judul player dibersihkan dari tag promosi umum seperti `[Official Video]`, `(Lyrics)`, `| Official Audio`, markup HTML, dan hashtag `#shorts`, tanpa membuang apostrof, `feat. Artist`, atau kata `Remix`.
- Visualizer batang sintetis diubah menjadi kartu sesi glass dengan piringan vinyl yang berputar perlahan selama audio diputar. Ini dekoratif, bukan visualizer beat, karena stream saat ini tidak mengekspos amplitudo PCM atau beat timestamp.
- Menambahkan tes formatter judul dan memperbarui metadata versi menjadi 5.0.44+22.

## Validasi

Paket dan struktur file diperiksa secara statis. Flutter SDK tidak tersedia di lingkungan pengerjaan ini, jadi `flutter analyze`, `flutter test`, build APK, dan uji sinkronisasi dua perangkat masih perlu dilakukan melalui GitHub Actions/perangkat nyata.
