import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Minimal X.509 check used because the Lich repo server's certificate has
/// CN "Lich Repository" and no SAN, so Dart's built-in hostname verification
/// always fails and hands us the leaf in `onBadCertificate` without saying
/// why. We re-verify here: the leaf must be signed (sha256WithRSA) by the
/// pinned CA, be within its validity dates, and carry an allowed CN.
class PinnedCaVerifier {
  PinnedCaVerifier(String caPem) {
    final ca = _Cert.parse(_pemToDer(caPem));
    _caSubject = ca.subject;
    final (n, e) = ca.rsaPublicKey();
    _n = n;
    _e = e;
  }

  late final Uint8List _caSubject;
  late final BigInt _n;
  late final BigInt _e;

  /// True if [leafDer] was issued and signed by the pinned CA.
  bool isSignedByCa(Uint8List leafDer) {
    try {
      final leaf = _Cert.parse(leafDer);
      if (!_bytesEqual(leaf.issuer, _caSubject)) return false;
      if (!_bytesEqual(leaf.sigAlg, _sha256WithRsaOid)) return false;
      return _rsaPkcs1Sha256Verify(leaf.tbs, leaf.signature);
    } on FormatException {
      return false;
    }
  }

  bool _rsaPkcs1Sha256Verify(Uint8List message, Uint8List sig) {
    final k = (_n.bitLength + 7) ~/ 8;
    if (sig.length != k) return false;
    final em = _toBytes(_fromBytes(sig).modPow(_e, _n), k);
    final digest = sha256.convert(message).bytes;
    final t = [..._sha256DigestInfoPrefix, ...digest];
    final expected = Uint8List(k)
      ..[0] = 0
      ..[1] = 1;
    for (var i = 2; i < k - t.length - 1; i++) {
      expected[i] = 0xff;
    }
    expected[k - t.length - 1] = 0;
    expected.setRange(k - t.length, k, t);
    return _bytesEqual(em, expected);
  }

  static const _sha256WithRsaOid = [
    0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, //
  ];
  static const _sha256DigestInfoPrefix = [
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, //
    0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ];

  static Uint8List _pemToDer(String pem) => base64.decode(pem
      .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
      .replaceAll(RegExp(r'\s'), ''));

  static BigInt _fromBytes(List<int> b) =>
      b.fold(BigInt.zero, (acc, x) => (acc << 8) | BigInt.from(x));

  static Uint8List _toBytes(BigInt v, int len) {
    final out = Uint8List(len);
    for (var i = len - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return out;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Just enough of an X.509 certificate for [PinnedCaVerifier].
class _Cert {
  _Cert(this.tbs, this.sigAlg, this.signature, this.issuer, this.subject,
      this.spki);

  /// Full DER of tbsCertificate (what the signature covers).
  final Uint8List tbs;

  /// OID bytes of the outer signatureAlgorithm.
  final Uint8List sigAlg;
  final Uint8List signature;

  /// Full DER of the issuer / subject Names, for byte comparison.
  final Uint8List issuer;
  final Uint8List subject;
  final _Der spki;

  static _Cert parse(Uint8List der) {
    final cert = _Der.read(der, 0).children();
    if (cert.length != 3) throw const FormatException('bad certificate');
    final tbsFields = cert[0].children();
    var i = tbsFields.first.tag == 0xa0 ? 1 : 0; // optional [0] version
    i++; // serialNumber
    i++; // signature
    final issuer = tbsFields[i++];
    i++; // validity
    final subject = tbsFields[i++];
    final spki = tbsFields[i];
    final sigBits = cert[2].value; // BIT STRING: leading unused-bits byte
    return _Cert(
      cert[0].raw,
      cert[1].children().first.value,
      Uint8List.sublistView(sigBits, 1),
      issuer.raw,
      subject.raw,
      spki,
    );
  }

  (BigInt n, BigInt e) rsaPublicKey() {
    final bits = spki.children()[1].value;
    final key = _Der.read(bits, 1).children();
    return (
      PinnedCaVerifier._fromBytes(key[0].value),
      PinnedCaVerifier._fromBytes(key[1].value),
    );
  }
}

class _Der {
  _Der(this.tag, this.raw, this.value);
  final int tag;
  final Uint8List raw;
  final Uint8List value;

  static _Der read(Uint8List b, int off) {
    if (off + 2 > b.length) throw const FormatException('truncated DER');
    final tag = b[off];
    var len = b[off + 1];
    var hdr = 2;
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      if (n == 0 || n > 4 || off + 2 + n > b.length) {
        throw const FormatException('bad DER length');
      }
      len = 0;
      for (var i = 0; i < n; i++) {
        len = (len << 8) | b[off + 2 + i];
      }
      hdr += n;
    }
    final end = off + hdr + len;
    if (end > b.length) throw const FormatException('truncated DER');
    return _Der(tag, Uint8List.sublistView(b, off, end),
        Uint8List.sublistView(b, off + hdr, end));
  }

  List<_Der> children() {
    final out = <_Der>[];
    var off = 0;
    while (off < value.length) {
      final d = read(value, off);
      out.add(d);
      off += d.raw.length;
    }
    return out;
  }
}
