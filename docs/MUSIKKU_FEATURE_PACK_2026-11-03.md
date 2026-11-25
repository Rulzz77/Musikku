# MusikKu Feature Pack — 3 November 2026

Paket ini menambahkan pusat fitur personal dan pengelolaan playlist tanpa mewajibkan akun/login atau mengubah mesin playback utama.

## Fitur yang ditambahkan pada paket ini

### MusikKu Studio
- **Music DNA:** ringkasan total waktu mendengar, artis teratas berdasarkan durasi, dan lagu paling sering diputar dari statistik lokal.
- **Artis favorit:** daftar artis yang ditandai pengguna, disimpan lokal melalui SharedPreferences.
- **MusikKu Flow:** mix mood sederhana (Chill, Happy, Focus, Energetic, Sad, Nostalgic) berdasarkan metadata lagu dalam riwayat lokal dan statistik dengar. Hasilnya diputar melalui callback antrean aplikasi. Ini bukan model rekomendasi cloud dan kualitasnya bergantung pada metadata/riwayat yang tersedia.
- **Penyaringan Flow:** lagu dapat disembunyikan dari Flow tanpa dihapus dari pencarian, playlist, favorit, atau riwayat.
- **Memories:** ringkasan 30 hari, lagu sering diputar, dan riwayat terbaru.
- **Theme Studio:** pilihan tema aplikasi yang sudah tersedia (System, Midnight Slate, AMOLED, Warm Paper, Pink Pastel).
- **Radio Diary manual:** menyimpan snapshot dari riwayat lagu terbaru agar dapat diputar kembali. Ini bukan perekaman otomatis semua sesi Radio.
- **Focus Timer:** timer 15/25/45/60 menit dengan opsi jeda musik saat selesai. Countdown menggunakan waktu akhir absolut agar nilai timer mengejar waktu yang terlewat saat aplikasi kembali aktif. Ini bukan alarm yang dijamin berbunyi setelah proses aplikasi dihentikan paksa.
- **Car Mode:** layar kontrol besar untuk lagu aktif, Previous/Play-Pause/Next dan pintasan lirik. Ini UI dalam aplikasi, bukan pengganti sistem Android Auto.

### Pengelolaan playlist
- Metadata playlist: deskripsi/catatan, folder, dan warna aksen.
- Urutkan playlist berdasarkan terbaru, nama, jumlah lagu, atau folder.
- Gabungkan isi satu playlist ke playlist lain dengan penghindaran duplikasi video ID.
- Pilih beberapa lagu lalu hapus sekaligus.
- Artwork playlist tetap memakai field cover independen yang sudah ada, sehingga tidak bergantung pada urutan lagu.

## Fitur yang sudah ada dan dipertahankan

Paket sumber sudah memiliki beberapa fitur terkait, yang tidak diimplementasikan ulang di sini: antrean dan penyimpanan antrean, Radio/Smart Shuffle yang ada, statistik dengar dasar, Crossfade fade-out, Sleep Timer, equalizer best-effort, penghemat data, notifikasi media/lock-screen melalui service pemutar, dan Listening Together berbasis ruang.

## Batasan yang belum diklaim sebagai fitur selesai

- Visualizer berbasis waveform/spectrum dari audio mentah memerlukan akses PCM. Player YouTube berbasis iframe tidak menyediakan stream PCM kepada aplikasi.
- Gapless playback sejati dan loudness normalization antar-track tidak dapat dijamin dari sumber iframe YouTube.
- Floating Lyrics di atas aplikasi lain memerlukan overlay permission dan implementasi native Android terpisah.
- Home Screen Widget membutuhkan implementasi native/widget extension Android dan iOS, belum ditambahkan oleh paket ini.
- Reaksi emoji dan polling MusikKu Party, serta filter pencarian lanjutan, ditambahkan pada pembaruan susulan. Lihat `MUSIKKU_REMAINING_FEATURES_UPDATE_2026-11-03.md` untuk cakupan dan batasannya.

## Pemeriksaan

Pemeriksaan statis yang dilakukan pada paket ini: keseimbangan delimiter/string komentar pada file Dart, keberadaan import/part relatif, parsing `pubspec.yaml` dan `analysis_options.yaml`, parsing Android XML, dan tes integritas ZIP. Flutter SDK tidak tersedia di lingkungan pembuatan, jadi `flutter analyze`, test suite, dan build APK harus dijalankan pada komputer pengembang.
