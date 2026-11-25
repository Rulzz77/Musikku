# Menjaga ukuran update MusikKu tetap kecil

Ada dua ukuran berbeda yang sering tertukar: ukuran APK yang diunduh pengguna dan ukuran repository saat developer melakukan `git push`.

## 1. APK yang diunduh pengguna

Workflow `MusikKu Secure Release` menerbitkan dua APK:

- `app-arm64-v8a-release.apk` untuk ponsel ARM64. Updater MusikKu memeriksa ABI perangkat dan memilih file ini lebih dulu.
- `app-release.apk` sebagai fallback universal untuk perangkat lama atau instalasi MusikKu yang belum mengenali APK khusus ABI.

Ini mengecilkan unduhan untuk mayoritas ponsel Android modern. Namun APK tetap paket instalasi penuh, bukan patch delta; perubahan satu file Dart tetap harus diunduh sebagai APK baru. Jangan commit APK ke repository. Biarkan GitHub Actions menerbitkannya sebagai Release asset.

Workflow release berjalan saat `pubspec.yaml` berubah atau dijalankan manual. Untuk membuat rilis baru, naikkan `version:` di `pubspec.yaml` agar nama tag versi tidak bentrok dengan release sebelumnya.

## 2. Ukuran repository Git

Folder `.gradle`, `build`, `.dart_tool`, `ephemeral`, `.idea`, APK, AAB, IPA, dan ZIP lokal tidak perlu ikut di Git. `.gitignore` sudah mencegah file baru tersebut ikut ter-stage. Aturan `.gitignore` tidak otomatis mengeluarkan file yang sudah pernah di-commit.

Dari root repository, keluarkan artefak generated yang telanjur tracked dari index Git (file lokal tetap ada):

```powershell
git rm -r --cached --ignore-unmatch .dart_tool build android/.gradle android/build android/app/build ios/Pods ios/Flutter/ephemeral linux/flutter/ephemeral macos/Flutter/ephemeral windows/flutter/ephemeral .idea
git rm --cached --ignore-unmatch -- '*.apk' '*.aab' '*.ipa' '*.zip'
git add .gitignore
git add -A
git status --short
```

Periksa hasil `git status --short` sebelum commit. Jangan menghapus `assets/`, source code, `pubspec.lock`, atau file konfigurasi yang memang dibutuhkan build hanya demi mengecilkan push.

Periksa ukuran Git lokal dengan:

```powershell
git count-objects -vH
```

Mengeluarkan file dari commit terbaru tidak menghapus salinan yang sudah ada di riwayat commit lama. Kalau ukuran repository tetap besar karena file binary pernah di-commit berkali-kali, riwayat perlu dibersihkan dengan `git filter-repo`; itu mengubah commit ID dan perlu dikoordinasikan untuk semua clone. Karena repo MusikKu sebelumnya pernah mengalami remote-ahead/rebase, jangan menjalankan `git push --force` atau rewrite history tanpa backup dan rencana sinkronisasi.
