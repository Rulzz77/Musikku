# MusikKu 5.0.41+19 — perbaikan sinkronisasi Dengerin Bareng

- Tamu meminta snapshot lagu terbaru segera setelah masuk kamar; host mengirim snapshot seketika.
- Snapshot state diberi sequence untuk mencegah pembaruan lama menimpa status terbaru.
- Saat audio host sedang dimuat, snapshot terbaru (termasuk status idle/unsupported) disimpan dan diterapkan segera setelah operasi sebelumnya selesai, tidak lagi dibuang.
- Snapshot stale dengan sequence yang lebih kecil diabaikan, termasuk event idle/unsupported yang datang terlambat.
- Panel kamar menampilkan status sinkronisasi lagu terpisah dari status koneksi jaringan.
- Tes regresi ditambahkan untuk pemilihan snapshot terbaru dan aksi `sync_request`.

Build dan tes perangkat dua HP harus tetap dijalankan lewat GitHub Actions/perangkat fisik sebelum dinyatakan terverifikasi.
