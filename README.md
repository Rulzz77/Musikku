<div align="center">

# 🎧 MusikKu

**Temukan musik. Impor playlist. Putar dengan MusikKu.**

![Version](https://img.shields.io/badge/version-4.5.0-1DB954?style=for-the-badge)
![Build](https://img.shields.io/badge/build-32-6C63FF?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?style=for-the-badge)

</div>

MusikKu adalah pemutar musik Android berbasis Flutter dengan pencarian musik, koleksi lokal, antrean, radio, lirik, dan impor playlist Spotify melalui file ekspor akun.

## ✨ Fitur

- 🔎 **Discovery musik** — cari lagu dan temukan versi yang tersedia di katalog MusikKu.
- 🎼 **Player & antrean** — kontrol playback, antrean lagu, lirik, timer tidur, dan efek audio.
- 📁 **Musik lokal** — telusuri dan putar file audio di perangkat.
- 💚 **Impor playlist Spotify** — impor metadata playlist dari `Playlist*.json` tanpa Spotify API, OAuth, Client ID, atau Premium.
- 🎨 **Personalisasi** — tema aplikasi dan pengaturan pemutaran.

## 📥 Impor playlist Spotify

Unduh **Account data** dari [halaman privasi Spotify](https://www.spotify.com/account/privacy/), ekstrak ZIP, lalu pilih file `Playlist*.json` melalui menu **Impor Spotify** di MusikKu. Metadata playlist disimpan lokal; file audio Spotify tidak ikut diimpor. Lihat [SPOTIFY_SETUP.md](SPOTIFY_SETUP.md) untuk catatan format dan batasan.

## 🧰 Teknologi

- Flutter / Dart
- Native Android Kotlin
- SharedPreferences untuk data koleksi lokal
- GitHub Actions untuk build dan GitHub Release otomatis

## 📌 Catatan

- MusikKu adalah proyek independen dan tidak berafiliasi dengan Spotify atau YouTube.
- Cover dan metadata visual tidak selalu tersedia dalam file ekspor Spotify.
- Hasil pencarian lagu harus dicocokkan dengan benar sebelum diputar.
- Status build dan pengujian mengikuti hasil CI terbaru.


## Pembaruan APK

GitHub Releases menyediakan APK universal untuk kompatibilitas updater versi lama dan APK split per arsitektur. Mulai MusikKu 4.5.1, updater otomatis memilih `app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, atau `app-x86_64-release.apk` sesuai ABI perangkat. Jika deteksi ABI tidak tersedia, updater memakai `app-release.apk` universal.
