# MusikKu 5.0.33+11 — perbaikan Dengerin Bareng dan Player

- Menambahkan shortcut **Dengerin bareng** pada grid **Langsung putar** di Beranda.
- Panel Dengerin Bareng dapat dibuka sebelum lagu dipilih; host bisa membuat kamar dulu dan mulai memutar lagu setelahnya.
- Untuk server Supabase yang sudah dikonfigurasi, join sekarang hanya meminta kode 8 digit. UI tidak menampilkan kolom IP, alamat server, atau link undangan.
- Kode kamar digunakan sebagai channel key Supabase Realtime agar teman di Wi-Fi atau jaringan seluler lain dapat bergabung.
- Konsumsi data dipindahkan ke halaman Pengaturan dan dihapus dari layar Player.
- Player menggunakan susunan vertikal yang lebih rapat: konten kontrol dimulai langsung setelah cover, mengurangi celah besar di antara cover dan kontrol.

## Pengaturan wajib

GitHub Actions Variables `SUPABASE_URL` dan `SUPABASE_PUBLISHABLE_KEY` harus diisi sebelum build. Tanpa konfigurasi itu, antarmuka memberi tahu server online belum siap dan tidak meminta IP lokal.
