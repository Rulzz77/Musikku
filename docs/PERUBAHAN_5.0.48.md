# MusikKu 5.0.48+26

## Perbaikan Next / Radio

- Normalisasi judul tidak lagi memecah tanda hubung internal seperti `Hati-Hati`.
- Atribusi `cover by ...` dan tag video dibersihkan sebelum fingerprint dibuat.
- Fingerprint Radio memprioritaskan segmen judul lagu dan menghindari nama channel/penyanyi yang diketahui.
- Riwayat lagu menyimpan objek video yang sudah diputar; pembandingan keluarga lagu memakai kecocokan judul dan toleransi variasi kata yang kecil.
- Deduplikasi diterapkan pada pool Radio dan fallback lokal agar cover/re-upload dengan judul yang sama tidak kembali dipilih.
- Nama penyanyi yang ditulis sebagai awalan pada judul cover dibersihkan jika cocok dengan channel atau atribusi cover. Untuk upload bertanda Cover dari kanal label/produksi, parser juga memilih sisi judul saat formatnya “Penyanyi - Judul”.
- Tes regresi ditambahkan untuk lagu ber-hyphen, cover dari penyanyi berbeda (termasuk format penyanyi-dulu), dan memastikan lagu berbeda dari penyanyi yang sama tetap dapat dipilih.
