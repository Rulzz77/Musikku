# MusikKu — mengaktifkan Dengerin Bareng lintas jaringan

Versi source: **5.0.32+10**. Koneksi online menggunakan Supabase Realtime Broadcast. Tidak memerlukan login pengguna, tetapi pemilik project perlu mengonfigurasi satu project Supabase terlebih dahulu.

Dokumentasi vendor: [Realtime Broadcast](https://supabase.com/docs/guides/realtime/broadcast) dan [Getting Started](https://supabase.com/docs/guides/realtime/getting_started).

## 1. Buat project Supabase

1. Buat project di https://supabase.com/dashboard.
2. Di **Project Settings / Connect**, salin **Project URL** dan **Publishable key** (`sb_publishable_...`).
3. Jangan pernah memasukkan `sb_secret_...` atau `service_role` ke aplikasi mobile. Hanya publishable key yang boleh dipakai di sisi klien.
4. Pastikan Realtime aktif untuk project. Implementasi ini memakai public Broadcast channel dengan ID kamar acak 128-bit sebagai bagian rahasia undangan; tidak ada tabel database yang perlu dibuat. Siapa pun yang memperoleh seluruh undangan dapat masuk, jadi bagikan undangan hanya kepada teman yang dipercaya.

## 2. Ambil dependency

```bash
flutter pub get
```

## 3. Jalankan aplikasi dengan konfigurasi online

Ganti nilai contoh dengan Project URL dan Publishable key milik project sendiri:

```bash
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY
```

Untuk APK release:

```bash
flutter build apk --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY
```

Dua nilai ini harus dipakai pada setiap build aplikasi yang ingin memakai mode online. Jangan unggah nilai rahasia server ke APK. URL dan publishable key bukan password admin.

## 4. Cara memakai

1. Host membuka Dengerin Bareng lalu memilih **Buat kamar baru**.
2. Tekan **Salin undangan** satu kali dan kirim teks undangan kepada teman.
3. Teman membuka menu yang sama dan menempelkan undangan ke kolom **Undangan online teman** lalu memilih **Gabung kamar**. Kode kamar sudah tertanam dalam undangan, jadi kolom kode boleh dibiarkan kosong.
4. Selama koneksi internet aktif, host mengirim status lagu setiap dua detik dan tamu mengirim heartbeat agar jumlah perangkat tersambung dapat diperbarui. Tidak perlu menyalin undangan ulang saat lagu berganti.

Catatan: undangan adalah semacam kunci kamar—bagikan hanya kepada orang yang dipercaya. Di tahap ini string `musikku://...` harus ditempel ke aplikasi; belum menjadi universal/app link yang otomatis membuka aplikasi ketika diklik dari chat. Audio tetap diputar terpisah oleh setiap perangkat dari sumber lagu yang didukung MusikKu. Ketersediaan lagu/iklan/buffering dapat membuat sinkronisasi sedikit berbeda.

Jika Supabase belum dikonfigurasi pada saat build, aplikasi tetap berjalan dalam mode lokal Wi-Fi/hotspot.
