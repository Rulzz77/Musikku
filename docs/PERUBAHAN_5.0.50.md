# MusikKu 5.0.50+28 — cover, Player, dan lirik

## Perubahan

- Radio/Next mencoba mengganti hasil yang secara eksplisit dilabeli sebagai cover dengan kandidat rekaman asli apabila judul, atribusi artis, dan sinyal channel cocok dengan keyakinan tinggi. Jika metadata atau hasil pencarian ambigu, sumber terpilih tetap dipakai daripada menebak.
- Cover Player digeser 18 dp ke bawah secara visual; ukuran cover tidak berubah.
- Lirik berjalan pada Player berupa teks langsung tanpa kartu/latar kaca.
- LRC dengan beberapa timestamp dalam satu baris dipecah menjadi baris bertanda waktu masing-masing; metadata offset LRC diterapkan dan waktu negatif dijepit ke nol.
- Hasil lirik diverifikasi terhadap metadata judul dan artis sebelum dipakai.
- Cache lirik menggunakan namespace `lyrics_v2` supaya hasil lirik lama yang berpotensi salah tidak terus dipakai.
- Scroll lirik direset saat lagu/lirik baru masuk.
- Tambah tes regresi untuk parser LRC, offset, pencocokan metadata lirik, dan identifikasi judul cover berbentuk kata kerja.

## Validasi

Source dan metadata versi diperiksa secara statis. Flutter SDK/Dart SDK tidak tersedia di lingkungan pengemasan ini, sehingga `flutter analyze`, `flutter test`, dan build APK harus dijalankan melalui GitHub Actions.
