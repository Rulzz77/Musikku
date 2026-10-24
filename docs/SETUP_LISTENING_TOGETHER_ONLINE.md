# MusikKu — Dengerin Bareng online lintas jaringan

Versi source: **5.0.38+16**. Koneksi online memakai Supabase Realtime Broadcast. Pengguna tidak perlu login, tetapi pembuat APK perlu mengonfigurasi satu project Supabase.

Dokumentasi vendor: [Realtime Broadcast](https://supabase.com/docs/guides/realtime/broadcast) dan [Getting Started](https://supabase.com/docs/guides/realtime/getting_started).

## 1. Buat project Supabase

1. Buat project di https://supabase.com/dashboard.
2. Di **Project Settings / Connect**, salin **Project URL** dan **Publishable key** (`sb_publishable_...`).
3. Jangan memasukkan `sb_secret_...` atau `service_role` ke aplikasi mobile. Gunakan publishable key saja.
4. Implementasi memakai public Realtime Broadcast channel; tidak perlu membuat tabel. Kode kamar 8 digit dipakai sebagai nama channel, jadi bagikan hanya kepada teman. Karena ini mode tanpa akun, siapa pun yang mengetahui/menebak kode dapat mencoba masuk.

## 2. Atur GitHub Actions Variables

Di repository GitHub buka **Settings → Secrets and variables → Actions → Variables**, lalu tambahkan:

- `SUPABASE_URL` — Project URL.
- `SUPABASE_PUBLISHABLE_KEY` — Publishable key.

Workflow release memerlukan dua variabel itu dan juga secret build/release yang sudah ada di repository.

## 3. Buat APK

Workflow release menjalankan `flutter pub get`, `flutter analyze`, tes, lalu build APK dengan variabel Supabase. Untuk build lokal:

```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY
```

Untuk APK release:

```bash
flutter build apk --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY
```

## 4. Cara memakai

1. Dari Beranda pilih **Dengerin bareng**, lalu tekan **Buat kamar**.
2. MusikKu menampilkan **kode 8 digit**. Salin kode itu sekali dan kirim ke teman.
3. Teman membuka shortcut **Dengerin bareng** di Beranda, memasukkan kode 8 digit, lalu menekan **Gabung pakai kode**. Tidak perlu memasukkan alamat IP, alamat server, atau link undangan.
4. Host dapat mulai memutar lagu setelah kamar dibuat. Tamu yang sudah bergabung juga dapat memakai tombol Play/Pause, Next/Previous, seek, Shuffle, dan Repeat; perintahnya dikirim ke host lewat Realtime. Pergantian lagu, play/pause, posisi, Shuffle, dan Repeat disinkronkan otomatis selama koneksi internet aktif. Host dan tamu sama-sama dapat mengirim kontrol, termasuk memilih lagu YouTube dari hasil pencarian; pemilihan tamu akan dikirim ke host agar semua perangkat berpindah ke lagu yang sama. Host tetap menjadi sumber status pemutaran yang disiarkan ke kamar. Tidak perlu mengirim kode ulang setiap lagu berganti.

Supabase berjalan di cloud, jadi laptop/PC pemilik project tidak harus menyala. Namun, HP host perlu menjalankan MusikKu dan tersambung ke internet selama sesi mendengarkan berlangsung. Pada paket Free, project dapat dijeda setelah sekitar 7 hari aktivitas database yang rendah. Karena event kamar memakai Broadcast dan tidak disimpan ke database, paket Free cocok untuk uji coba tetapi bukan jaminan selalu aktif untuk produksi; pertimbangkan paket berbayar jika butuh uptime yang lebih konsisten.

Audio tetap diputar secara terpisah di masing-masing perangkat dari sumber yang didukung MusikKu. Ketersediaan lagu, iklan, atau buffering berbeda dapat membuat posisi pemutaran sedikit tidak sama. Kode kamar dipakai sebagai kunci akses praktis, bukan autentikasi akun yang kuat; jangan membagikannya secara publik.

Jika URL atau publishable key tidak dimasukkan saat APK dibangun, panel Dengerin Bareng akan menunjukkan bahwa server online belum dikonfigurasi dan tidak menyediakan alur IP lokal.
