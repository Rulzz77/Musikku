<div align="center">

# 🎧 MusikKu

### Musik favoritmu, dalam satu ruang.

**Aplikasi musik Android berbasis Flutter** dengan pencarian, discovery, pemutar musik, antrean, koleksi lokal, dan kontrol yang bisa disesuaikan.

<p>
  <img src="https://img.shields.io/badge/Versi-4.2.0-DB3E67?style=for-the-badge&logo=flutter&logoColor=white" alt="Versi 4.2.0" />
  <img src="https://img.shields.io/badge/Build-26-24202B?style=for-the-badge" alt="Build 26" />
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android" />
  <img src="https://img.shields.io/badge/Framework-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
</p>

<p>
  <em>Discover · Play · Queue · Repeat</em>
</p>

---

[✨ Fitur](#-fitur-utama) · [🚀 Mulai](#-mulai-di-komputermu) · [🧩 Arsitektur](#-gambaran-arsitektur) · [🔐 Konfigurasi](#-konfigurasi) · [🧪 Status QA](#-status-kualitas-dan-pengujian)

</div>

> MusikKu menggabungkan pengalaman discovery musik modern dengan pemutaran musik lokal Android. Proyek ini terus berkembang; lihat bagian **Status QA** dan **Batasan yang diketahui** sebelum memakai build untuk distribusi.

## ✨ Fitur utama

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>🔎 Discovery & pencarian</h3>
      <ul>
        <li>Tab <b>Beranda, Sampel, Jelajahi, Subscription,</b> dan <b>Koleksi</b>.</li>
        <li>Pencarian katalog YouTube dengan konteks musik dan cache.</li>
        <li>Eksplorasi berdasarkan genre, feed populer, dan riwayat yang tersedia.</li>
        <li>Status loading, hasil kosong, error, dan opsi coba lagi.</li>
      </ul>
    </td>
    <td width="50%" valign="top">
      <h3>▶️ Playback & antrean</h3>
      <ul>
        <li>Pemutar penuh dan mini-player.</li>
        <li>Antrean lagu, shuffle, repeat, dan navigasi lagu berikut/sebelumnya.</li>
        <li>Radio dan pemutaran berkelanjutan/auto-next.</li>
        <li>Kontrol media Android dan dukungan playback di background dari implementasi native.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>📚 Koleksi pribadi</h3>
      <ul>
        <li>Memindai dan memutar file audio yang ada di perangkat.</li>
        <li>Favorit dan playlist lokal.</li>
        <li>Riwayat/rekap pendengaran yang tersedia di aplikasi.</li>
        <li>Menu aksi lagu: antrekan, favorit, playlist, radio, channel, dan salin tautan sesuai dukungan item.</li>
      </ul>
    </td>
    <td width="50%" valign="top">
      <h3>🎚️ Kontrol & personalisasi</h3>
      <ul>
        <li>Panel lirik ketika sumber lirik tersedia.</li>
        <li>Sleep timer berbasis durasi atau akhir lagu.</li>
        <li>Preset/efek audio yang bergantung pada dukungan perangkat.</li>
        <li>Tema terang, gelap, dan AMOLED serta opsi hemat data.</li>
      </ul>
    </td>
  </tr>
</table>

### 🧭 Area aplikasi

| Area | Kegunaan |
|---|---|
| **Beranda** | Hub utama untuk menemukan dan membuka musik. |
| **Sampel** | Discovery dari feed dan riwayat yang tersedia, termasuk aksi putar mix. |
| **Jelajahi** | Menemukan musik lewat genre dan pencarian. |
| **Subscription** | Akses area subscription/channel yang disediakan source aplikasi. |
| **Koleksi** | Mengakses musik, favorit, dan playlist pengguna. |
| **Player** | Kontrol playback, antrean, lirik, sleep timer, dan pengaturan audio. |

## 🖼️ Tampilan

Screenshot aplikasi belum disertakan dalam paket source ini. Untuk menjaga dokumentasi tetap akurat, bagian ini tidak memakai gambar mockup seolah-olah hasil tangkapan layar aplikasi sungguhan. Screenshot bisa ditambahkan nanti ke `docs/screenshots/` lalu ditautkan dari sini.

## 🚀 Mulai di komputermu

### Prasyarat

- Flutter SDK yang kompatibel dengan batas Dart pada `pubspec.yaml`.
- Android SDK dan toolchain build Android.
- Perangkat Android atau emulator untuk menjalankan aplikasi.
- API key YouTube Data API v3 untuk fitur katalog/pencarian YouTube.

### 1. Ambil source code

```bash
git clone <URL_REPOSITORY_KAMU>
cd MusikKu-4.2.0
```

> Jika source didapat dari file ZIP, ekstrak ZIP terlebih dahulu, lalu buka direktori yang berisi `pubspec.yaml`.

### 2. Pasang dependensi

```bash
flutter pub get
```

### 3. Jalankan aplikasi

```bash
flutter run --dart-define=YOUTUBE_API_KEY=KUNCI_API_KAMU
```

Ganti `KUNCI_API_KAMU` dengan API key milikmu. Tanpa key yang valid, katalog/pencarian yang bergantung pada YouTube Data API dapat tidak menghasilkan data.

### 4. Jalankan pemeriksaan

```bash
flutter analyze
flutter test
```

### 5. Build APK release

```bash
flutter build apk --release --dart-define=YOUTUBE_API_KEY=KUNCI_API_KAMU
```

File APK umumnya dihasilkan pada:

```text
build/app/outputs/flutter-apk/app-release.apk
```

**Penting:** proyek ini memeriksa konfigurasi signing untuk packaging release. Siapkan signing key milikmu sebelum membuat rilis; instruksi ada di bagian berikut.

## 🔐 Konfigurasi

### YouTube Data API

1. Buat atau pilih project di Google Cloud Console.
2. Aktifkan **YouTube Data API v3**.
3. Buat API key dan terapkan batasan API serta batasan aplikasi yang sesuai.
4. Teruskan key saat menjalankan/build dengan `--dart-define=YOUTUBE_API_KEY=...`.
5. Pantau kuota dan penggunaan API pada project Google Cloud.

<details>
<summary><b>⚠️ Catatan keamanan API key</b></summary>

`--dart-define` memudahkan konfigurasi, tetapi nilai yang disertakan dalam aplikasi client tidak boleh dianggap sebagai rahasia yang mustahil diekstrak. Batasi key melalui Google Cloud. Untuk aplikasi yang didistribusikan luas, pertimbangkan proxy/backend yang sesuai dan jangan pernah memasukkan kredensial server ke source code atau APK.

Jangan commit API key, password, file `key.properties`, atau keystore ke repository.

</details>

### Android release signing

Contoh konfigurasi tersedia di `android/key.properties.example`.

1. Buat keystore release milikmu.
2. Salin `android/key.properties.example` menjadi `android/key.properties`.
3. Isi `storeFile`, `storePassword`, `keyAlias`, dan `keyPassword` dengan nilai yang benar.
4. Pastikan file keystore berada di lokasi yang dirujuk `storeFile`.
5. Simpan file rahasia di luar Git dan buat backup keystore secara aman.

Build release memang akan dihentikan jika konfigurasi signing atau file keystore belum ditemukan. Jangan mendistribusikan aplikasi dengan debug key.

## 🧩 Gambaran arsitektur

Source dibagi ke beberapa bagian agar layar, model data, layanan, dan integrasi Android tidak bercampur seluruhnya.

```text
MusikKu/
├── android/
│   └── app/src/main/kotlin/com/musikku/app/
│       ├── MainActivity.kt
│       ├── PlaybackService.kt
│       ├── AudioEffectsController.kt
│       ├── YoutubeCaptionController.kt
│       └── ...                 # Bridge dan utilitas native Android
├── lib/
│   ├── main.dart               # Entry point
│   ├── app_info.dart           # Nama dan versi aplikasi
│   ├── models/                 # Model lagu, playlist, antrean, lirik, statistik
│   ├── pages/                  # Layar utama, pengaturan, pencarian, statistik
│   │   └── home_page/           # Bagian-bagian state dan UI halaman utama
│   ├── services/               # Pencarian, playback, cache, radio, storage, dll.
│   ├── theme/                  # Warna dan tema aplikasi
│   └── widgets/                # Player, daftar lagu, lirik, kartu, bottom sheet
├── test/                       # Tes otomatis yang tersedia
├── pubspec.yaml
└── README.md
```

### Stack utama

| Teknologi | Peran |
|---|---|
| **Flutter / Dart** | UI dan logika aplikasi. |
| **Kotlin / Android** | Playback service, player bridge, efek audio, dan integrasi sistem. |
| **YouTube Data API v3** | Data katalog/pencarian yang menggunakan API key. |
| **Shared Preferences & file cache** | Preferensi dan cache lokal tertentu. |
| **Android media APIs** | Integrasi pemutaran media dan kontrol perangkat. |

## 🧪 Status kualitas dan pengujian

Status pada paket source saat dokumentasi ini dibuat:

| Pemeriksaan | Status |
|---|---|
| Struktur ZIP/source | ✅ Arsip diperiksa |
| Konsistensi versi | ✅ `pubspec.yaml` dan `lib/app_info.dart` menggunakan `4.2.0` / build `26` |
| `flutter analyze` | ⏳ Perlu dijalankan di mesin dengan Flutter SDK |
| `flutter test` | ⏳ Perlu dijalankan di mesin dengan Flutter SDK |
| APK release | ⏳ Belum dinyatakan tervalidasi; membutuhkan toolchain dan signing lokal |
| Uji perangkat nyata | ⏳ Perlu dilakukan pada versi Android dan perangkat target |

Periksa hasil analyzer dan test sebelum menganggap build siap untuk distribusi. Perilaku pemutar, izin media, efek audio, notifikasi, dan playback background sebaiknya diuji pada perangkat Android nyata.

## ⚠️ Batasan yang diketahui

- **Musik offline** berarti file audio yang sudah tersimpan di perangkat pengguna; ini bukan fitur download offline dari katalog streaming.
- Ketersediaan lirik bergantung pada sumber dan data lirik yang dapat ditemukan.
- Efek audio/equalizer bergantung pada implementasi serta dukungan perangkat Android.
- Fitur katalog/pencarian bergantung pada API key, kuota, jaringan, serta respons layanan eksternal.
- Sinkronisasi Premium penuh, download katalog streaming, cast, pengalaman AI, dan feed podcast personal tidak diklaim tersedia dalam paket ini. Fitur tersebut memerlukan integrasi resmi, backend, izin, dan/atau layanan tambahan yang sesuai.
- Aplikasi ini bukan aplikasi resmi YouTube atau Google dan tidak berafiliasi dengan keduanya. Nama layanan pihak ketiga disebut hanya untuk menjelaskan integrasi.

## 🗺️ Roadmap yang disarankan

- [ ] Jalankan analyzer dan semua tes otomatis pada toolchain target.
- [ ] Uji alur playback, antrean, permission, dan lifecycle pada beberapa versi Android.
- [ ] Tambahkan screenshot asli untuk tiap area utama.
- [ ] Siapkan CI untuk analyzer, tes, dan pemeriksaan format.
- [ ] Evaluasi integrasi tambahan hanya jika API, izin, keamanan, dan ketentuan layanan mendukung.

## 🤝 Berkontribusi

1. Buat branch untuk perubahanmu.
2. Jaga API key, signing key, serta data pribadi agar tidak masuk commit.
3. Jalankan `flutter analyze` dan `flutter test` sebelum mengirim perubahan.
4. Sertakan langkah reproduksi untuk bug serta screenshot/video asli jika perubahan memengaruhi UI.
5. Jelaskan perangkat dan versi Android yang digunakan ketika melaporkan masalah playback.

## 📄 Lisensi dan penggunaan

Paket source ini tidak menyertakan file lisensi yang menetapkan izin redistribusi. Sebelum memublikasikan fork atau mendistribusikan ulang, tetapkan lisensi proyek dan periksa lisensi dependency serta kewajiban penggunaan API/layanan pihak ketiga.

---

<div align="center">

**MusikKu v4.2.0 · Build 26**

_Dibuat untuk pengalaman mendengarkan musik yang terasa lebih personal._

</div>
