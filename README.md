# Lich Repo Browser

A standalone, cross-platform browser for Lich scripts, covering both the
`;repository` server and Jinx repos: a Flutter app for
Windows / macOS / Linux / Android / iOS.

## Features

- One list across the Lich repository and Jinx repos (the same file from several sources shows once)
- Boolean search: `AND`/`OR`/`NOT` (`&` `|` `-` `!`), parentheses, `"phrases"`, fields
  (`author:` `tag:` `name:` `comment:` `source:` `game:` `type:` `version:` `is:`), wildcards,
  and `downloads:` `rating:` `votes:` `size:` `updated:` `age:` comparisons (`?` in the search box)
- Favorites, "new & updated since last visit", installed / update-available filters
- Downloads to the right Lich folder (`scripts/`, `data/`, `maps/`); replaced files are backed up
  to `<lich>/temp/repo-browser-backups/`
- Installed tab: which local files have updates, with per-file and bulk update
- Rate Lich repository scripts (1–10), add your own Jinx repos, browse map images in a gallery
- Catalogs cached for instant, offline-capable startup; phones save via the share sheet

## Layout

- `core/` — pure Dart package with the protocol clients (used by the app)
  - `lib/src/lich_repo_source.dart` — `;repository` server (TLS on `repo.lichproject.org:7157`)
  - `lib/src/jinx_source.dart` — Jinx repos (`<repo>/manifest.json` over HTTPS)
  - `lib/src/cert_check.dart` — verifies the Lich server cert against the pinned CA
  - `bin/spike.dart` — command-line tool that exercises both
- `app/` — Flutter GUI for Windows / macOS / Linux / Android / iOS

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
- `rate` (`file`, `game`, `rating` 1–10) answers with a header only: `success` or `error`.
- The server rate-limits connections (resets after roughly a dozen in quick succession), so
  the app never makes per-file requests in bulk; update checks use the list's sizes instead.
- The client sends `client 2.74` (the repository.lic version). Check with the maintainers
  whether a third-party client should identify itself differently.

**Jinx**
- Default repos: `extras.repo.elanthia.online`, `ffnglichrepoarchive.netlify.app`,
  `elanthia-online.github.io/mapdb-backup-{gs,dr}`.
- `manifest.json` → `available[]` with `file, type, md5, last_commit, header, tags, version, author`.
- Despite its name, `md5` is a **base64 SHA-1** of the file.
- The `mirror` repo is an archive: every `last_commit` is the snapshot date (2020-12-19), so the
  app never treats it as the newest copy of a file available elsewhere.
- No CORS headers, so a plain web build can't read these without a proxy.
