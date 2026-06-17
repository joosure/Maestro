# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

Bahasa: [English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文](./README.zh-TW.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [More](./LANGUAGES.md)

## Jalankan AI Agent dari tugas proyek nyata.

Maestro menghubungkan **sistem proyek, repositori Git, dan coding agents** ke dalam satu alur eksekusi tugas engineering.

Daripada memantau satu chat AI satu per satu, Maestro dapat membaca tugas baru atau tugas yang siap dikerjakan dari sistem seperti Linear atau TAPD, membuat ruang kerja terisolasi untuk setiap tugas, menyiapkan repositori Git target, menjalankan AI Agent yang sesuai, mencatat prosesnya, lalu menulis hasilnya kembali ke sistem proyek.

Maestro bukan coding agent baru.

Maestro membantu tim menjawab pertanyaan yang muncul setelah agents mulai berguna: tugas berasal dari mana, kode berasal dari mana, agent berjalan di mana, bagaimana beberapa tugas berjalan paralel, apa yang berubah, apakah hasilnya dapat dipercaya, dan bagaimana tim dapat meninjau atau memulihkan eksekusi.

> **Symphony membuktikan bahwa tugas proyek dapat menggerakkan agents. Maestro mengubah pola itu menjadi platform engineering yang dapat dioperasikan.**

---

## Satu contoh

Bayangkan ada tugas baru di TAPD atau Linear:

> Halaman checkout gagal ketika pengguna memakai dua kupon.

Dengan Maestro, tugas itu dapat menjadi eksekusi agent yang terlihat:

1. Maestro menyinkronkan atau membaca tugas dari TAPD, Linear, atau sistem proyek lain.
2. Maestro membuat ruang kerja terisolasi di lingkungan runtime miliknya sendiri.
3. Maestro melakukan clone atau checkout repositori Git target ke dalam ruang kerja itu.
4. Maestro menjalankan Codex, Claude Code, OpenCode, atau agent lain yang didukung dengan konteks tugas, salinan repositori, dan alat yang diizinkan.
5. Agent menganalisis salinan repositori dan menyiapkan perubahan kode, hasil analisis, atau saran review.
6. Maestro mencatat diff, log, panggilan alat, ringkasan, dan tautan terkait.
7. Maestro menulis hasilnya kembali ke sistem proyek agar tim dapat meninjau, melanjutkan, atau mengambil alih.

Tujuannya bukan membiarkan agent berjalan tanpa kendali. Intinya adalah:

> **Satu tugas proyek menjadi eksekusi engineering oleh agent yang terisolasi, tercatat, dapat ditinjau, dan dapat diambil alih.**

Ruang kerja terisolasi penting karena setiap tugas memiliki direktori, salinan repositori, log, dan file sementara sendiri. Beberapa proyek dan tugas dapat berjalan paralel tanpa saling mengganggu; jika gagal, eksekusi lebih mudah diperiksa, dibersihkan, dan dicoba lagi.

---

## Mengapa ini penting

Coding agents semakin baik dalam menulis kode. Namun tim membutuhkan lebih dari sekadar pembuatan kode.

Tim perlu jawaban praktis:

- Tugas datang dari sistem proyek mana?
- Repositori Git dan branch mana yang terkait?
- Agent mana yang harus menjalankannya?
- Agent berjalan di mana?
- Bagaimana beberapa eksekusi tetap terisolasi?
- Apa yang berubah?
- Apakah manusia bisa meninjau hasilnya?
- Apa yang terjadi jika gagal?
- Bagaimana tim memahami proses yang terjadi?

Maestro dibangun di sekitar pertanyaan-pertanyaan itu.

---

## Yang bisa Anda lakukan dengan Maestro

### 1. Mengubah tugas bug menjadi Pull Request

Bug muncul di TAPD atau Linear. Maestro membaca tugas, membuat ruang kerja terisolasi, menyiapkan repositori Git target, menjalankan agent, membiarkan agent menganalisis dan mengubah kode, lalu menulis tautan PR, ringkasan, dan pertanyaan terbuka kembali ke tugas.

### 2. Menganalisis requirement sebelum coding

Jika requirement belum jelas, Maestro dapat meminta agent menghasilkan scope, risiko, acceptance criteria, dan pertanyaan klarifikasi sebelum implementasi.

### 3. Merapikan tugas yang belum siap dimulai

Jika konteks kurang, Maestro dapat menampilkan asumsi, blocker, dan pertanyaan alih-alih membiarkan agent menebak.

### 4. Melakukan triage pekerjaan masuk

Maestro dapat membantu mengklasifikasikan tugas baru, menyarankan prioritas, mengidentifikasi risiko, dan merekomendasikan status berikutnya.

### 5. Membandingkan beberapa coding agents

Jalankan tugas serupa dengan Codex, Claude Code, atau OpenCode dan bandingkan hasil, mode kegagalan, log, dan catatan delivery.

### 6. Mencoba secara lokal tanpa akun nyata

Gunakan alur lokal `memory/no_repo/mock` untuk memahami Maestro tanpa menghubungkan Linear, TAPD, GitHub, CNB, Codex, Claude Code, atau OpenCode.

---

## Dukungan integrasi saat ini

Sistem di bawah ini adalah **integrasi yang didukung dan template bawaan**, bukan sistem yang tertanam di dalam Maestro. Linear, TAPD, GitHub, CNB, Codex, Claude Code, dan OpenCode tetap merupakan sistem atau alat eksternal. Maestro menghubungkan dan mengorkestrasinya.

Adapter sistem proyek:

- Linear
- TAPD
- Memory, untuk tes lokal dan demo

Adapter agent:

- Codex
- Claude Code
- OpenCode
- Mock, untuk tes lokal dan demo

Adapter platform kode:

- GitHub
- CNB
- Memory, untuk tes lokal dan demo

Workflow template yang disediakan:

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro dirancang untuk tumbuh dengan lebih banyak sistem proyek, platform kode, agents, dan workflow templates.

---

## Cara kerjanya

```text
Tugas di sistem proyek
   ↓
Maestro membaca/menyinkronkan tugas dan memutuskan apakah perlu ditangani
   ↓
Maestro membuat ruang kerja terisolasi di lingkungan runtime miliknya
   ↓
Repositori Git target disiapkan di dalam ruang kerja itu
   ↓
AI Agent berjalan dengan tugas, salinan repositori, dan alat yang diizinkan
   ↓
Agent menghasilkan perubahan kode, hasil analisis, atau saran review
   ↓
Maestro mencatat diffs, log, panggilan alat, ringkasan, dan tautan
   ↓
Maestro menulis hasilnya kembali ke sistem proyek untuk review atau handoff
```

Bagi developer, alur yang sama dapat dipahami lewat beberapa titik ekstensi:

- **Sistem proyek**: asal tugas, seperti Linear atau TAPD.
- **Repositori Git dan platform kode**: tempat kode di-clone dan tempat branch, PR, review, serta checks terjadi.
- **Agents**: siapa yang mengerjakan, seperti Codex, Claude Code, atau OpenCode.
- **Workflows**: jenis pekerjaan, seperti memperbaiki bug, menganalisis requirement, merapikan tugas, triage, atau menyarankan review.
- **Ruang kerja dan runtime**: tempat setiap eksekusi agent terjadi, bagaimana ia diisolasi, dan bagaimana eksekusi berjalan paralel.
- **Catatan**: log, diff, komentar tugas, ringkasan, dan informasi lain yang dapat ditinjau.

---

## Quick start

```bash
git clone https://github.com/joosure/Maestro.git
cd Maestro
cd elixir
mise trust
mise install
cd ..
make -C elixir deps
make -C elixir test
make -C elixir build
cd elixir
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

Buka dashboard opsional:

```text
http://localhost:4000
```

Demo ini memakai data memori dan Mock Agent. Ini cara paling aman untuk memahami proyek sebelum menghubungkan sistem nyata.

> Brand publik memakai **Maestro**. Beberapa nama runtime masih memakai `symphony` untuk kompatibilitas, termasuk entrypoint CLI dan sebagian environment variables.

---

## Menggunakan sistem nyata

Setelah demo lokal, Anda dapat menghubungkan sistem proyek nyata, repositori Git, dan coding agent.

### Contoh: TAPD + GitHub + Codex

```bash
export TAPD_API_USER=...
export TAPD_API_PASSWORD=...
export TAPD_WORKSPACE_ID=...
export SOURCE_REPO_URL=https://github.com/owner/repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo

./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template tapd/github/codex \
  --port 4000
```

### Contoh: Linear + GitHub + Codex

```bash
export LINEAR_API_KEY=...
export LINEAR_PROJECT_SLUG=...
export SOURCE_REPO_URL=https://github.com/owner/repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo

./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template linear/github/codex \
  --port 4000
```

Sebelum memakai repositori nyata atau kredensial berizin tinggi, baca:

- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Apa itu Maestro, dan apa yang bukan

Maestro adalah:

- platform eksekusi tugas engineering yang menghubungkan sistem proyek, repositori Git, dan coding agents;
- cara menjalankan AI agents dari tugas proyek nyata;
- lapisan workflow untuk coding, analisis requirement, refinement tugas, triage, dan saran review;
- cara yang lebih aman untuk mencoba, membandingkan, dan mengelola beberapa coding agents.

Maestro bukan:

- model bahasa besar baru;
- pengganti Codex, Claude Code, atau OpenCode;
- alat untuk melewati review, testing, atau keputusan release tim;
- sistem yang sebaiknya diberi akses repositori lalu ditinggalkan tanpa pengawasan.

---

## Status proyek

Maestro adalah software tahap awal yang sedang aktif dikembangkan.

Cocok untuk:

- mempelajari bagaimana workflow agent berbasis tugas dapat bekerja;
- menjalankan demo lokal memory/mock;
- membuat prototipe integrasi baru;
- bereksperimen dengan sistem nyata di lingkungan terkendali.

Berhati-hatilah sebelum:

- mengizinkan agents mengubah repositori nyata atau melakukan push branch;
- mengizinkan agents menulis status atau komentar ke sistem proyek nyata;
- menggunakan kredensial berizin tinggi atau token pribadi;
- membagikan satu runtime environment untuk beberapa tim;
- melanjutkan ke test, release, atau production tanpa review manusia.

Prinsip dasar:

> **Otomatisasi dengan berani. Pasang gate dengan hati-hati. Jaga jejak eksekusi tetap terlihat.**

---

## Pelajari lebih lanjut

- [Roadmap](./ROADMAP.id.md)
- [Languages](./LANGUAGES.md)
- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Attribution

Maestro started as a fork of [OpenAI Symphony](https://github.com/openai/symphony). Symphony demonstrated that project tasks can drive coding agents. Maestro extends that idea into a broader platform for real engineering workflows.

---

## License

Maestro is licensed under the GNU Affero General Public License version 3 (AGPL-3.0-only). Portions derived from OpenAI Symphony retain their Apache-2.0 attribution and notice requirements. Review `LICENSE`, `NOTICE`, `LICENSES/Apache-2.0.txt`, `MODIFICATIONS.md`, `SOURCE.md`, and `THIRD_PARTY_LICENSES.md` before using or distributing Maestro.
