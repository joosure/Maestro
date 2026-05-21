# Maestro Roadmap

Bahasa: [English](./ROADMAP.md) · [简体中文](./ROADMAP.zh-CN.md) · [Bahasa Indonesia](./ROADMAP.id.md) · [More](./LANGUAGES.md)

## Tujuan

Maestro memiliki tujuan sederhana:

> **Membuat AI agents lebih mudah, aman, dan andal untuk tim engineering nyata.**

Banyak coding agents sudah bisa menulis kode. Tim membutuhkan lebih dari sekadar pembuatan kode:

- pekerjaan harus datang dari sistem nyata seperti TAPD, Linear, dan platform masa depan;
- kode harus datang dari repositori Git dan branch yang dikonfigurasi dengan jelas;
- setiap eksekusi harus memiliki ruang kerja terisolasi agar tugas tidak saling mengganggu;
- manusia harus dapat memahami apa yang agent lakukan, apa yang berubah, dan mengapa gagal;
- langkah berisiko tinggi harus tetap dapat ditinjau;
- tim harus dapat memperluas penggunaan secara bertahap, bukan membuka semua izin sejak hari pertama.

Roadmap ini disusun berdasarkan nilai bagi pengguna, bukan nama modul internal.

---

## Jangka pendek: membuat Maestro lebih mudah dicoba

Pengguna baru seharusnya dapat memahami dan menjalankan Maestro tanpa mempelajari seluruh arsitektur terlebih dahulu.

Rencana kerja:

- demo lokal yang lebih sederhana;
- instruksi Quick Start yang lebih jelas;
- screenshot, GIF, atau video singkat;
- contoh tugas yang menunjukkan alur lengkap;
- penjelasan jelas mengapa ruang kerja terisolasi penting: paralelisme, isolasi, pembersihan, dan kemudahan review;
- penjelasan untuk nama kompatibilitas `symphony` yang masih ada;
- jalur jelas dari demo lokal ke konfigurasi proyek nyata.

Skenario yang ingin dibuat lebih mudah ditunjukkan:

- tugas TAPD ke GitHub Pull Request;
- tugas Linear ke GitHub Pull Request;
- analisis requirement sebelum coding;
- triage pekerjaan masuk;
- saran reviewer;
- perbandingan Codex, Claude Code, dan OpenCode pada tugas serupa.

Sukses berarti pembaca baru dapat menjawab dalam beberapa menit:

> “Apa yang Maestro lakukan, dan mengapa tim saya mungkin membutuhkannya?”

---

## Berikutnya: menghubungkan agents ke workflow proyek nyata

Maestro harus membantu agents bekerja dari sistem proyek yang sudah digunakan tim, bukan memaksa tim membuat antrean tugas baru.

Rencana kerja:

- memperbaiki alur TAPD dan Linear yang ada;
- membuat status tugas, komentar, tautan, dan hasil lebih mudah dipahami;
- membuat workflow template lebih mudah ditemukan, disalin, dan disesuaikan;
- mendukung lebih banyak tugas umum: bug fixes, small features, analisis requirement, refinement tugas, triage, dan saran review;
- membedakan dengan jelas dukungan integrasi saat ini dari target ekstensi masa depan;
- menyiapkan integrasi seperti Jira, GitHub Issues, GitLab, Gitea, Bitbucket, dan Feishu Project.

Sukses berarti tim dapat mulai dari workflow proyek yang sudah ada tanpa mengubah cara mengelola pekerjaan hanya untuk memakai agents.

---

## Jangka menengah: membuat kerja agent lebih dapat dipercaya

Tim tidak seharusnya percaya pada eksekusi hanya karena agent berkata “selesai”.

Rencana kerja:

- riwayat eksekusi yang lebih jelas;
- ringkasan eksekusi yang lebih mudah dibaca;
- tautan yang lebih baik antara tugas, perubahan Git, log, dan materi review;
- alasan kegagalan yang lebih jelas;
- redaction log yang lebih baik;
- dashboard yang lebih berguna;
- checkpoint terlihat sebelum menulis ke sistem proyek nyata, melakukan push branch, atau membuat PR;
- pemisahan jelas antara demo lokal, evaluasi terpercaya, pilot tim, dan operasi produksi.

Sukses berarti reviewer dapat menjawab:

- Apa yang agent lakukan?
- Dari tugas dan repositori Git mana ia bekerja?
- Apa yang berubah?
- Mengapa ia berhenti?
- Apa yang masih butuh konfirmasi manusia?
- Apakah aman untuk dilanjutkan?

---

## Jangka panjang: membantu tim memakai agents dalam skala lebih besar

Demo satu agent berguna. Penggunaan tingkat tim membutuhkan operasi yang lebih kuat.

Rencana kerja:

- menjalankan beberapa tugas secara bersamaan dengan aman;
- menjaga workspace dan catatan terpisah untuk proyek dan tugas berbeda;
- memilih agent berbeda untuk jenis tugas berbeda;
- mengelola akun, kredensial, kuota, dan biaya dengan lebih jelas;
- memperbaiki lingkungan runtime tingkat tim;
- memperbaiki retry dan recovery;
- mendukung titik persetujuan manusia yang lebih jelas;
- membantu tim membandingkan efektivitas nyata dari agents dan workflows berbeda.

Sukses berarti tim dapat memperluas penggunaan agents secara bertahap sambil menjaga keamanan, biaya, dan kualitas tetap terkendali.

---

## Dokumentasi dan komunitas

Maestro harus mudah dipahami sebelum terlihat kuat.

Rencana kerja:

- menjaga README utama tetap singkat dan berbasis contoh;
- memindahkan detail teknis mendalam ke dokumen terpisah;
- memelihara English dan Simplified Chinese secara aktif;
- menjaga terjemahan lain tetap tersedia dan menerima perbaikan komunitas;
- menambahkan panduan kontribusi untuk sistem proyek, agents, platform kode, dan workflow templates;
- menerbitkan lebih banyak contoh skenario engineering nyata.

Sukses berarti kontributor dapat menemukan titik masuk yang berguna tanpa membaca seluruh codebase terlebih dahulu.

---

## Bukan tujuan untuk saat ini

Maestro tidak berusaha membantu tim melewati review, testing, atau keputusan release.

Yang lebih penting bagi kami:

- menghubungkan agents ke tugas nyata;
- membuat sumber kode dan sumber tugas terlihat;
- menjaga proses eksekusi dapat dilacak;
- mempertahankan kontrol manusia pada langkah berisiko tinggi;
- menyimpan catatan eksekusi yang berguna;
- memperluas otomatisasi hanya saat kepercayaan meningkat.

Otomatisasi harus berkembang bersama bukti, bukan keinginan.

---

## Fokus saat ini

Fokus saat ini adalah membuat Maestro lebih mudah dipahami, lebih mudah dicoba, dan lebih aman dievaluasi:

1. menyederhanakan README publik;
2. menambahkan roadmap dengan bahasa sederhana;
3. memperbaiki panduan demo lokal;
4. menjelaskan dukungan integrasi saat ini tanpa menyebut sistem eksternal sebagai “tertanam”;
5. menjelaskan mengapa workspace terisolasi penting;
6. menambahkan contoh untuk TAPD, Linear, GitHub, CNB, dan kombinasi agent nyata;
7. menjaga detail teknis tetap tersedia tanpa memaksa setiap pembaca baru memulai dari sana.

---

## Cara berkontribusi

Kontribusi yang berguna:

- contoh yang lebih baik;
- dokumentasi yang lebih jelas;
- workflow template yang lebih aman;
- integrasi sistem proyek baru;
- integrasi coding agent baru;
- integrasi platform kode baru;
- perbaikan dashboard;
- cakupan tes untuk workflow nyata;
- review terjemahan oleh penutur asli.

Mulailah dari alur lokal memory/mock, lalu bergerak bertahap ke sistem nyata.
