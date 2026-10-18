<div align="center">

# 🎧 MusikKu

**Musik favoritmu, dalam satu tempat.**

![Version](https://img.shields.io/badge/version-4.6.3-D94B70?style=for-the-badge)
![Build](https://img.shields.io/badge/build-36-6C63FF?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?style=for-the-badge)

</div>

MusikKu adalah aplikasi musik Android untuk menjelajahi musik, mengelola favorit dan playlist, mendengarkan radio, serta memutar audio dari YouTube dan perangkat.

## ✨ Fitur utama

- 🔎 **Jelajahi musik** — cari lagu, telusuri genre, dan temukan musik baru.
- 🎛️ **Pemutar musik** — mini-player, antrean, shuffle, repeat, lirik, timer tidur, dan efek audio.
- 💗 **Koleksi personal** — favorit, riwayat dengar, playlist, dan statistik.
- 📁 **Musik lokal** — pindai serta putar file audio yang tersimpan di perangkat.
- 📻 **Radio otomatis** — lanjutkan mendengarkan dengan lagu yang serupa.
- 🎨 **Tampilan fleksibel** — tema sistem, terang, gelap, dan AMOLED.
- 🔄 **Pembaruan aplikasi** — cek rilis baru dari dalam aplikasi.

## 🎵 Navigasi

**Beranda · Mix · Jelajahi · Langganan · Koleksi**

## 🧰 Teknologi

Flutter / Dart · Native Android Kotlin · SharedPreferences · GitHub Actions

## 📌 Catatan

MusikKu adalah proyek independen. Ketersediaan hasil pencarian dan pemutaran bergantung pada layanan serta koneksi yang tersedia.

## 📦 Pembaruan APK

GitHub Releases menyediakan APK universal untuk kompatibilitas updater lama dan APK split per arsitektur untuk unduhan lebih kecil. Updater versi baru memilih APK yang cocok dengan ABI perangkat secara otomatis.


### Playback source safety (4.6.3)

Shuffle keeps the current session within one source type: YouTube tracks shuffle with YouTube tracks, and device-local files shuffle with local files. If the queue contains items from both sources, Shuffle selects only matching items and leaves the others queued. Normal queue playback may still mix sources when the user explicitly chooses that queue order.


### Source-safe Shuffle (4.6.3)

Shuffle keeps YouTube tracks and local files in separate playback sessions. Mixed history/Mix lists are normalized to the selected track source; source-incompatible queue entries remain queued during Shuffle. Normal playback queue order remains explicit-user controlled.
