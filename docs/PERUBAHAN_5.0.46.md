# MusikKu 5.0.46+24 — Radio relevan tanpa chart populer

- Memperbaiki lint `use_null_aware_elements` pada payload kontrol Dengerin Bareng.
- Seed Radio default memakai judul + artis + `similar songs`, bukan query genre generik yang mencari lagu populer.
- Fallback chart `mostPopular` dihapus dari `RadioService` dan pencarian Radio. Jika tidak ada hasil terkait, MusikKu tidak menggantinya dengan lagu chart acak.
- YouTube Radio search menggunakan `order=relevance` dan cache key baru; daftar tidak diurutkan lagi berdasarkan view count/freshness.
- Skor radio tidak memberi bonus view count. Kandidat gaya tidak diketahui tidak mencampuri kandidat dengan genre terkait yang sudah dikenali.
- Fallback daftar lama/favorit/riwayat hanya menerima genre yang diketahui dan terkait dengan track aktif.
- Tes diperbarui untuk seed spesifik, pembatasan genre, dan skor yang tidak dipengaruhi view count.

`flutter analyze`, `flutter test`, dan build APK perlu dijalankan di lingkungan Flutter/GitHub Actions untuk validasi penuh.
