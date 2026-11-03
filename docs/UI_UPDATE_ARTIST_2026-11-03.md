# MusikKu — Pembaruan Halaman Artis

## Arah desain

Halaman yang diperbarui adalah **profil artis**, bukan halaman detail playlist. Saat pengguna membuka Noah, Rony Parulian, atau artis lain, halaman menampilkan identitas artis dan katalog lagu resminya.

## Perubahan

- Banner channel digunakan sebagai gambar hero. Jika banner tidak tersedia, foto profil channel dipakai sebagai fallback.
- Nama artis dan jumlah lagu resmi diletakkan di atas hero dengan overlay gelap agar terbaca.
- Tombol Shuffle dan Putar memulai sesi dari katalog artis. Shuffle mengacak salinan daftar untuk sesi itu, tanpa mengubah data katalog.
- Daftar lagu memakai artwork persegi, judul, nama artis, dan menu opsi lagu; kartu tebal dihilangkan.
- Tab Album & playlist publik dihapus dari profil artis agar halaman tidak terasa seperti playlist.
- Pengambilan playlist publik channel tidak lagi dilakukan saat membuka profil artis. Uploads channel tetap dibaca untuk mendapatkan daftar lagu.
- Filter lagu resmi, pengecualian karaoke/cover/fan edit, pemuatan lagu berikutnya, dan callback pemutaran yang sudah ada tetap dipertahankan.

## Pemeriksaan

ZIP sumber diperbarui setelah perubahan. Flutter/Dart SDK tidak tersedia pada lingkungan ini, jadi `dart format`, `flutter analyze`, dan build APK belum dapat dijalankan. Jalankan `flutter pub get`, `dart format lib/pages/artist_page.dart`, dan `flutter analyze` pada mesin pengembangan sebelum rilis.
