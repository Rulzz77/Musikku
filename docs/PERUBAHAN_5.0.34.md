# MusikKu 5.0.34+12 — perbaikan sinkronisasi online dan posisi Player

## Dengerin Bareng
- Memperbaiki pembacaan event Supabase Realtime yang payload-nya dibungkus pada field `payload`; event `room_join`, `room_join_result`, heartbeat, leave, room-close, dan status lagu sekarang dinormalisasi sebelum dibaca.
- Memeriksa hasil pengiriman Broadcast supaya kegagalan realtime terlihat di status aplikasi, bukan diam-diam dianggap berhasil.
- Menambahkan permintaan join ulang ketika koneksi realtime tersambung kembali setelah putus sementara.
- Menambahkan unit test untuk envelope broadcast Supabase dan format pesan langsung.

## Player
- Mengurangi tinggi header sebesar 8dp dan memangkas celah kecil di bawah cover/keterangan.
- Menyesuaikan anggaran tinggi cover agar ukurannya tetap sama setelah header dipadatkan.
- Menghapus animasi slide vertikal ketika Player dibuka; transisi tetap fade agar halaman tidak terasa bergerak naik-turun.

## Build dan tes
- Menyamakan `pubspec.yaml`, `app_info.dart`, dan ekspektasi versi pada `app_info_test.dart` ke 5.0.34+12.
- Tes Flutter dan build APK tetap harus dijalankan di GitHub Actions atau komputer yang memiliki Flutter SDK.
