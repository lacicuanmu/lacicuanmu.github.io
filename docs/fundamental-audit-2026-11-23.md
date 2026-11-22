# Audit Fundamental Laci Cuanmu — 23 November 2026

## Ringkasan eksekutif

Audit awal dilakukan pada repository `lacicuanmu/lacicuanmu.github.io`, terutama `index.html`, `manifest.json`, dan `supabase/transaction-evidence.sql`.

**Kesimpulan:** aplikasi sudah memiliki fondasi produk yang nyata (autentikasi, penyimpanan lokal, sinkronisasi akun, transaksi, laporan, OCR, dan arsip bukti privat), tetapi belum layak dinyatakan siap untuk skala banyak usaha/pengguna tanpa penguatan pada konsistensi data, konflik sinkronisasi, keamanan database, dan pengujian.

Audit ini merupakan inspeksi kode statis awal. Ini bukan penetration test, audit konfigurasi langsung Supabase, atau uji runtime di perangkat.

## Temuan prioritas

### P1 — Risiko kehilangan/pergantian data saat sinkronisasi multi-perangkat

- Seluruh state usaha dikirim sebagai satu objek JSON ke satu baris `books` per kombinasi akun/aplikasi.
- Proses sinkronisasi membandingkan `updated_at` dan dirty flag, lalu melakukan push atau mengganti state lokal dengan state cloud.
- Tidak terlihat mekanisme merge per transaksi, revision number, optimistic concurrency check, atau conflict resolution untuk dua perangkat yang mengubah data pada waktu berdekatan.
- Dampak potensial: perubahan dari perangkat yang lebih dulu tersinkron dapat menimpa perubahan perangkat lain (last-write-wins).

**Rekomendasi:** sebelum multi-device dipakai serius, tambahkan revision/version check dan strategi konflik yang tidak diam-diam membuang perubahan. Jangka menengah, pindahkan entitas penting ke tabel relasional per pengguna.

### P1 — Kebijakan keamanan tabel `books` belum dapat diverifikasi

- Frontend memanggil REST Supabase untuk membaca/menulis `books` dengan filter `app` dan token pengguna.
- SQL yang tersedia di repository hanya mengatur bucket arsip bukti `transaction-evidence`; belum ditemukan migration/schema/policy tabel `books`.
- Karena itu, isolasi data antar pengguna melalui RLS untuk tabel `books` belum dapat dipastikan dari repository.

**Rekomendasi:** verifikasi di Supabase bahwa RLS aktif dan policy SELECT/INSERT/UPDATE/DELETE membatasi `user_id = auth.uid()`. Pastikan juga ada unique constraint yang sesuai untuk mencegah baris ganda, misalnya pada `(user_id, app)`. Jangan menganggap filter frontend sebagai kontrol keamanan.

### P1 — Kebenaran laporan untuk diskon transaksi hasil OCR

- Transaksi penjualan hasil OCR menyimpan `price` setelah diskon, serta menyimpan `originalGross` dan `discount` sebagai properti tambahan.
- Agregasi `calc()` menghitung penjualan sebagai `qty * price`, tetapi tidak memasukkan `originalGross` atau mengakumulasikan diskon.
- Akibatnya angka yang diagregasi merupakan nilai setelah diskon, bukan omzet kotor sebelum diskon. Laporan belum bisa menampilkan rekonsiliasi omzet kotor → diskon → dasar setelah diskon secara konsisten.

**Rekomendasi:** tetapkan definisi baku: omzet kotor, diskon, nilai penjualan setelah diskon, biaya platform, pajak dipotong, kas diterima, HPP, dan laba. Terapkan satu fungsi perhitungan bersama untuk dashboard, laporan, dan CSV. Buat test case untuk transaksi lama dan transaksi OCR.

### P1 — Penyimpanan lokal gagal secara diam-diam

- Fungsi penyimpanan lokal menangkap error `localStorage.setItem` tetapi tidak memberi sinyal kepada pengguna.
- Jika storage penuh atau ditolak browser, aplikasi dapat melanjutkan alur seolah penyimpanan lokal berhasil.

**Rekomendasi:** fungsi save harus mengembalikan status sukses/gagal dan menampilkan peringatan yang jelas. Jangan mengonfirmasi transaksi tersimpan jika penulisan lokal dan/atau sinkronisasi yang dijanjikan belum berhasil.

### P2 — Satu objek JSON membatasi skalabilitas dan audit trail

- Produk, transaksi, catatan, pajak, karyawan, dan data lain berada di satu state JSON.
- Pola ini sederhana dan cocok untuk prototipe/MVP, tetapi seluruh state harus dibaca/ditulis ulang; query per periode, agregasi server-side, histori perubahan, dan update paralel menjadi sulit.

**Rekomendasi:** jangan migrasi mendadak. Rancang migrasi bertahap ke tabel relasional seperti `businesses`, `transactions`, `products`, `expenses`, `tax_obligations`, dan `transaction_evidence`, dengan `user_id`/business ownership, foreign key, indeks, constraints, dan RLS. Pertahankan jalur impor data lama.

### P2 — Session token berada di localStorage

- Session aplikasi menyimpan access token dan refresh token di localStorage.
- Ini pola yang umum untuk frontend statis, tetapi token dapat terbaca oleh JavaScript yang berjalan pada origin yang sama jika terjadi XSS.

**Rekomendasi:** kurangi permukaan XSS, audit semua penggunaan `innerHTML` dan escaping data pengguna, jangan pernah memasukkan secret service-role ke frontend, dan pertimbangkan arsitektur backend/BFF dengan cookie HttpOnly ketika aplikasi naik kelas.

### P2 — PWA belum menunjukkan dukungan offline penuh

- `manifest.json` tersedia.
- Tidak ditemukan file service worker standar (`sw.js` atau `service-worker.js`) pada pemeriksaan path repository, dan tidak ditemukan registrasi service worker pada kode yang diperiksa.
- Manifest sendiri tidak menyediakan cache offline aplikasi.

**Rekomendasi:** setelah alur data stabil, tambahkan service worker dengan strategi cache yang aman. Jangan cache respons privat/API Supabase secara sembarangan.

### P2 — Identitas transaksi memakai ID acak pendek

- Generator ID saat ini menggunakan `Math.random()` dan potongan string pendek.
- Collision mungkin jarang, tetapi tidak ideal sebagai identitas utama transaksi ketika jumlah data meningkat atau sinkronisasi multi-perangkat berlangsung.

**Rekomendasi:** gunakan `crypto.randomUUID()` dengan fallback yang sesuai, dan tetap tegakkan unique constraint di database.

### P2 — Pemeriksaan duplikat OCR belum kuat

- Hash bukti dibentuk dari teks OCR yang dinormalisasi menggunakan hash 32-bit.
- OCR yang sedikit berbeda dapat lolos, dan hash pendek memiliki risiko collision.

**Rekomendasi:** simpan fingerprint kriptografis SHA-256 jika tersedia, gabungkan dengan metadata penting, dan jadikan deteksi duplikat sebagai peringatan yang bisa ditinjau, bukan satu-satunya kontrol.

## Hal yang sudah baik

- Ada pemisahan data lokal dan cloud sync serta penanda dirty state.
- Arsip bukti transaksi menggunakan bucket privat, bukan public bucket.
- SQL arsip bukti membatasi folder pertama berdasarkan `auth.uid()` untuk insert/select/delete.
- Bukti asli dapat dihubungkan ke transaksi melalui metadata path.
- OCR mewajibkan pengguna meninjau hasil sebelum transaksi disimpan.
- Kewajiban pajak dipisahkan dari transaksi belanja agar tidak otomatis menghitung kewajiban sebagai biaya.
- Struktur `norm()` menyediakan default untuk beberapa properti agar data lama lebih kompatibel.

## Batas audit yang belum selesai

Hal-hal berikut belum dapat dinyatakan aman/lulus karena membutuhkan akses atau pengujian tambahan:

1. RLS dan constraint tabel `books` di proyek Supabase aktif.
2. Konfigurasi Auth (email confirmation, password policy, session expiry, rate limits).
3. Pengujian upload/download Storage dengan akun berbeda untuk memastikan isolasi.
4. Pengujian dua perangkat mengubah data bersamaan.
5. Pengujian backup lalu restore ke akun/perangkat bersih.
6. Uji transaksi dengan diskon, fee, pajak, retur, dan pembelian multi-item.
7. Uji browser nyata, Android 10, PWA terpasang, kondisi offline, storage penuh, dan koneksi putus di tengah simpan.
8. Audit semua jalur render HTML untuk kemungkinan XSS.

## Urutan perbaikan yang direkomendasikan

1. **Validasi keamanan Supabase:** RLS, unique constraint, Storage policy, dan Auth.
2. **Benahi model perhitungan transaksi:** satu definisi angka untuk gross, discount, net sales, fee, tax withheld, cash received, COGS, dan profit.
3. **Perkuat penyimpanan dan sinkronisasi:** error handling, versioning, conflict detection, dan recovery.
4. **Bangun test suite data:** data lama, transaksi baru, OCR, diskon, pajak, dan CSV.
5. **Rancang migrasi relasional bertahap:** tanpa menghapus dukungan data JSON lama sebelum migrasi tervalidasi.
6. **Perkuat PWA dan keamanan frontend.**

## Status

- Audit statis awal: selesai.
- Perubahan kode aplikasi: tidak dilakukan dalam audit ini.
- Uji runtime/perangkat: belum dilakukan.
- Audit konfigurasi Supabase aktif: belum dilakukan.
