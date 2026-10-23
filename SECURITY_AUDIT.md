# MusikKu — catatan audit keamanan

Tanggal pemeriksaan: 23 Oktober 2026

## Perubahan yang diterapkan

- Tema visual memakai palet charcoal + teal/mint + amber. Dock navigasi memakai kaca transparan dengan lensa netral yang mengikuti gerakan jari dan memperbesar ikon di dekatnya; aksen violet tidak dipakai untuk indikator dock.
- Player memakai latar gradien yang stabil, cover album persegi yang berukuran tetap berdasarkan lebar layar, dan transisi fade tanpa zoom. Pergantian lagu tidak lagi memperbesar cover sebagai latar layar penuh atau menggeser slot cover utama.
- WebView pemutar tetap mengaktifkan JavaScript/DOM storage yang diperlukan YouTube, tetapi akses file/content URI dinonaktifkan, mixed content HTTP diblokir, Safe Browsing diaktifkan pada Android O+, dan error sertifikat SSL selalu dibatalkan.
- Updater otomatis sekarang hanya menawarkan/menyetujui APK jika metadata GitHub menyediakan SHA-256 remote yang valid. Checksum lokal hasil download tidak lagi dianggap sebagai bukti keaslian payload awal.
- Konfigurasi Android yang sudah ada dipertahankan: cleartext traffic ditolak, Android backup dimatikan, service pemutaran dan FileProvider tidak diekspor, serta FileProvider dibatasi ke direktori updater.

## Perubahan lanjutan UI dan Mix — 23 Oktober 2026

- Ikon dock mendapat efek magnifikasi saat disentuh/di-swipe, dengan kaca buram yang tetap netral dan blur yang diturunkan agar lebih ringan pada perangkat Android.
- Tombol Mix menggunakan statistik pemutaran lokal: sebuah lagu harus sudah dimulai minimal dua kali dan punya sekurangnya 30 detik waktu dengar tercatat. Urutan mengikuti jumlah pemutaran, waktu dengar, dan lebih sedikit skip; lagu yang tidak lagi ada di riwayat terbaru tetap dapat dipulihkan dari metadata statistik.
- Test unit ditambahkan untuk memastikan lagu yang hanya diputar sekali atau sering dilewati tidak otomatis masuk Mix Kamu.
- `.gitattributes` ditambahkan untuk menjaga LF pada kode/config lintas platform dan CRLF pada script Windows. Saat menerapkan ke repository yang sudah ada, cek perubahan `git status` sebelum melakukan normalisasi massal.

## Temuan yang masih perlu ditindaklanjuti

### 1. YouTube Data API key adalah konfigurasi publik pada aplikasi klien — risiko sedang

`YOUTUBE_API_KEY` diterima melalui `String.fromEnvironment`/`--dart-define`, bukan ditulis sebagai literal di source. Namun, nilai yang dimasukkan saat build tetap dapat diekstrak dari APK. Batasi key di Google Cloud hanya untuk YouTube Data API v3, atur kuota dan alert, serta jangan gunakan key itu untuk layanan lain. Untuk perlindungan lebih kuat gunakan backend/proxy dengan rate limit; jangan menganggap `--dart-define` sebagai penyimpanan rahasia.

### 2. Verifikasi SHA-256 pada updater — tindakan wajib untuk setiap rilis

Unduhan dan cache updater diblokir bila metadata GitHub tidak menyediakan SHA-256 remote yang valid. Pastikan setiap rilis menyertakan digest SHA-256 dan lakukan uji update dari versi lama sebelum distribusi. Digest ini melindungi integritas file yang diunduh; kepercayaan pada penerbit tetap bergantung pada akun/repository GitHub dan tanda tangan APK. Android Package Installer tetap memeriksa kompatibilitas tanda tangan aplikasi ketika melakukan update.

### 3. Izin instalasi APK dari sumber lain

`REQUEST_INSTALL_PACKAGES` diperlukan untuk updater mandiri. Jika aplikasi disalurkan lewat Google Play, tinjau kebijakan distribusi terkait izin ini; untuk Play distribution, gunakan mekanisme update yang didukung Play apabila memungkinkan.

### 4. Belum bisa diverifikasi tanpa build dan pengujian perangkat

Audit statis dari source tidak bisa membuktikan bahwa audio background, pencarian, updater, atau seluruh layar tetap berfungsi pada setiap versi Android. Jalankan `flutter analyze`, `flutter test`, build release bertanda tangan, lalu uji instalasi/update, playback screen-off, pergantian lagu, rotasi, dan jaringan gagal di perangkat nyata. Dalam lingkungan pemeriksaan ini Flutter/Dart SDK tidak tersedia, jadi perintah tersebut belum dapat dijalankan di sini.

## Temuan file distribusi

Jangan membagikan `.git`, `android/local.properties`, `.dart_tool`, cache Gradle, folder build, file `key.properties`, atau keystore dalam ZIP source. Paket hasil perbaikan akan menghilangkan file lokal/hasil build tersebut. Pemeriksaan source yang tersedia tidak menemukan literal API key/token/keystore password yang tampak nyata; file `android/key.properties.example` hanya berisi placeholder.
