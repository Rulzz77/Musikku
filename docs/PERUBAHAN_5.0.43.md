# MusikKu 5.0.43+21

- Mengganti ruang kosong besar di Player dengan visualizer audio bergaya glass yang bergerak hanya saat musik diputar. Ukuran dan posisi cover tetap sama.
- Menjaga kontrol utama tetap berada di area bawah player, tanpa area hitam kosong yang tidak memiliki fungsi di antara metadata dan kontrol.
- Koreksi drift Dengerin Bareng dipicu pada selisih sekitar 1,8 detik (sebelumnya 2,8 detik) agar posisi audio tamu lebih cepat mendekati host.
- Menambahkan tes regresi untuk ambang koreksi drift.

Validasi build penuh harus dilakukan melalui GitHub Actions/Flutter SDK. Stream audio di masing-masing perangkat tetap dapat memulai dengan jeda buffering yang berbeda; sinkronisasi berkala memperbaiki selisih posisi setelah audio siap.
