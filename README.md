# Lich Repo Browser

A standalone, cross-platform browser for Lich scripts, covering both the
`;repository` server and Jinx repos. The goal is a Flutter app for
Windows / macOS / Linux / Android / iOS.

## Layout

- `core/` — pure Dart package with the protocol clients (reused by the future Flutter app)
  - `lib/src/lich_repo_source.dart` — `;repository` server (TLS on `repo.lichproject.org:7157`)
  - `lib/src/jinx_source.dart` — Jinx repos (`<repo>/manifest.json` over HTTPS)
  - `lib/src/cert_check.dart` — verifies the Lich server cert against the pinned CA
  - `bin/spike.dart` — command-line tool that exercises both
- `app/` — Flutter GUI (phase 2, not started)

## Running the spike

Requires the Flutter SDK (includes Dart); here it lives in `~/development/flutter`.

```bash
cd core
dart pub get
dart run bin/spike.dart list bigshot            # search every source
dart run bin/spike.dart list --source jinx      # only Jinx repos
dart run bin/spike.dart info bigshot.lic --source lich
dart run bin/spike.dart download bigshot.lic --out /tmp
dart test
```

## Protocol notes (learned from repository.lic / jinx.lic and live testing)

**Lich repository** (`;repository`)
- One TLS connection per request. The request is a single line of `key\tvalue\t...`;
  the response is a header line like that, followed by `size` bytes (gzip if `compression gzip`).
- The server cert (CN `Lich Repository`, no SAN) is signed by a private root CA embedded in
  repository.lic. Dart's hostname check always rejects it, so `onBadCertificate` re-verifies
  the RSA signature against the pinned CA, the validity dates and the CN.
- `list` columns: `file, game, size, last update, author, downloads, rating total, rating count, tags`.
- `list-comments`: `file, game, comments`, where `\x14` means tab and `\x12` means newline.
- `inspect` returns `versions` (`;`-separated, older versions only) and usually an empty body,
  so the detail view falls back to the script's own `=begin`/`=end` header.
- The client sends `client 2.74` (the repository.lic version). Check with the maintainers
  whether a third-party client should identify itself differently.

**Jinx**
- Default repos: `extras.repo.elanthia.online`, `ffnglichrepoarchive.netlify.app`,
  `elanthia-online.github.io/mapdb-backup-{gs,dr}`.
- `manifest.json` → `available[]` with `file, type, md5, last_commit, header, tags, version, author`.
- Despite its name, `md5` is a **base64 SHA-1** of the file.
- No CORS headers, so a plain web build can't read these without a proxy.
