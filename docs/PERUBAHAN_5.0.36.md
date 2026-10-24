# MusikKu 5.0.36+14 — perbaikan seed artis Radio

- Radio kini memulai kandidat dari pencarian yang membawa judul lagu dan nama artis, bukan chart musik populer umum.
- Hasil pencarian berbasis lagu diutamakan; chart kategori Musik tetap menjadi fallback saat hasil terkait tidak tersedia.
- Seed song-radio dibersihkan dari label seperti Official Audio/Music Video dan suffix Topic agar pencarian tidak tercemar metadata unggahan.
- Query `similar songs` tidak lagi ditambahi kata `lagu Indonesia`, yang bisa menggeser rekomendasi lintas bahasa.
- Pool besar tidak lagi mencampur banyak lagu dengan genre tak dikenali bila kandidat dengan style yang cocok sudah tersedia. Pool kecil tetap memiliki fallback agar Radio tidak cepat berhenti.
- Menambah tes regresi seed Radio dan ranking kandidat.

Catatan: YouTube Music menggunakan sistem rekomendasi internal yang tidak tersedia lewat YouTube Data API publik. Perubahan ini mendekatkan perilaku Next ke Song Radio berbasis konteks lagu, tetapi tidak mengklaim meniru algoritma internal YouTube Music secara identik. Pencarian memakai bucket khusus `search.list` (batas default 100 panggilan per hari; bukan 100 unit dari bucket kuota umum). Hasilnya disimpan di cache dan dipakai ulang sehingga menekan Next tidak membuat query baru selama pool masih tersedia. Lihat https://developers.google.com/youtube/data/determine_quota_cost.


## Fix CI: artist seed case normalization

- Memperbaiki `_artistKey`: hapus suffix channel terlebih dahulu, lalu normalisasi teks dengan lowercase sebelum menghapus tanda baca.
- Kasus `Taylor Swift - Topic` sekarang menjadi `taylor swift`, bukan `aylor wift`.
- Tes seed Radio kini memeriksa hasil tepat `anti-hero taylor swift similar songs`.
