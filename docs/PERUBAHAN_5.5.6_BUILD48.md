# MusikKu 5.5.6+48 — Spotify count clarification & album artwork

- Spotify embed yang berhenti tepat di 100 baris ditandai sebagai daftar parsial; angka 100 tidak lagi disebut sebagai jumlah total playlist.
- Sisa lagu dapat ditempel dalam format `Judul<TAB>Artis` atau `Judul — Artis`; urutan dan duplikat dijaga. Tanpa Spotify API atau data tambahan yang diberikan pengguna, baris setelah batas embed publik tidak dapat dibaca otomatis.
- Parser Spotify membaca nama album jika payload embed menyediakannya; matcher juga membaca nama album hanya dari metadata album kandidat atau baris `Album:` dalam deskripsi auto-generated YouTube.
- Artwork mencari sampul depan rilisan berdasarkan album bila tersedia, lalu rekaman + artis utama yang cocok. Hanya gambar front cover yang disetujui di MusicBrainz/Cover Art Archive yang diterima, dan thumbnail 1200px diprioritaskan.
- Bila sumber katalog tidak memiliki sampul terverifikasi, fallback adalah thumbnail kualitas tertinggi dari video YouTube yang benar-benar dipilih, bukan gambar hasil pencarian acak. Jika `maxresdefault` tidak ada, widget mencoba thumbnail asli.
- UnifiedArtwork dipakai untuk kartu lagu dan daftar statistik; statistik juga menyimpan nama artis utama terpisah dari kredit lengkap.
- Cache artwork dinaikkan ke v3 agar hasil pencarian lama tidak menimpa aturan baru.


### Perbaikan lanjutan: jumlah playlist dan artwork

- Pembacaan jumlah track publik diperluas untuk variasi `totalLength`, `numberOfTracks`, `itemCount`, `totalItems`, serta deskripsi yang secara eksplisit mengiklankan jumlah lagu. Nilai 100 pada batas embed tetap dianggap jumlah terlihat/minimum, bukan total pasti.
- Metadata album/artis dari deskripsi auto-generated YouTube hanya diterima jika deskripsi diawali bukti `Provided to YouTube by` dan baris judul cocok dengan lagu yang sedang diperiksa.
- Thumbnail hasil pencarian YouTube kini memilih `maxres`, `high`, `standard`, `medium`, lalu `default`.
- Cache artwork dinaikkan ke v4 agar hasil resolusi lama dibangun ulang; sampul CAA yang dipilih harus approved + front, dan pemilih memilih ukuran terbesar yang tersedia. Jika katalog metadata tidak punya sampul valid, aplikasi memakai thumbnail dari video terpilih.
