/// Pure-Dart COSY request signing and WAF body codec for Qoder.
/// References: decolua/9router (MIT) and CLIProxyAPIPlus.
/// No 9Router server or Qoder CLI process is used.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' show
    AESEngine, CBCBlockCipher, KeyParameter, ParametersWithIV;
import 'qoder_direct_oauth.dart';

abstract final class QoderCosy {
  static const _modulus =
      'c0f22307e5cd362e296bb04470f6de8fbf935ce24e8fcf511a0e2701329769'
      'c4a76e499bb938036a52af1eaf818cf79a2600620e3ce87e371d2ca6d858'
      '03606a1b3fa5e874643c9ed2db7e85673ef7227fca56e2e7c08f0927609bb'
      '896a9f24be1782099a66016a5bfdc3f1ff756bfc9e88d7b5dc5be30bf45a02'
      '23a00ebcecf';
  static const _std =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  static const _custom =
      '_doRTgHZBKcGVjlvpC,@aFSx#DPuNJme&i*MzLOEn)sUrthbf%Y^w.(kIQyXqWA!';
  static final _rand = Random.secure();

  static String uuid() {
    final b = Uint8List.fromList(
      [for (var i = 0; i < 16; i++) _rand.nextInt(256)],
    );
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String encodeBody(List<int> plaintext) {
    final b64 = base64Encode(plaintext);
    final third = b64.length ~/ 3;
    final scrambled = b64.substring(b64.length - third) +
        b64.substring(third, b64.length - third) +
        b64.substring(0, third);
    return String.fromCharCodes([
      for (final c in scrambled.codeUnits)
        c == 61 ? 36 : _custom.codeUnitAt(_std.indexOf(String.fromCharCode(c))),
    ]);
  }

  /// PKCS#1 v1.5 encryption with the *public* Qoder modulus. CSPRNG padding.
  /// This compatibility mode is required by the private COSY protocol.
  static String wrapKey(String key) {
    final data = utf8.encode(key);
    const size = 128;
    final pad = size - data.length - 3;
    if (pad < 8) throw const QoderAuthException('COSY key is too long.');
    final bytes = <int>[0, 2];
    for (var i = 0; i < pad; i++) {
      var value = 0;
      while (value == 0) value = _rand.nextInt(256);
      bytes.add(value);
    }
    bytes..add(0)..addAll(data);
    var n = BigInt.zero;
    for (final v in bytes) n = (n << 8) | BigInt.from(v);
    final publicModulus = BigInt.parse(_modulus, radix: 16);
    final cipher = n.modPow(BigInt.from(65537), publicModulus);
    final hex = cipher.toRadixString(16).padLeft(size * 2, '0');
    return base64Encode([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  static String _encryptInfo(Map<String, Object?> info, String key) {
    final plaintext = utf8.encode(jsonEncode(info));
    final padding = 16 - plaintext.length % 16;
    final padded = Uint8List(plaintext.length + padding)
      ..setRange(0, plaintext.length, plaintext);
    for (var i = plaintext.length; i < padded.length; i++) {
      padded[i] = padding;
    }
    final secret = Uint8List.fromList(utf8.encode(key));
    final aes = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(secret), secret));
    final encrypted = Uint8List(padded.length);
    for (var i = 0; i < padded.length; i += 16) {
      aes.processBlock(padded, i, encrypted, i);
    }
    return base64Encode(encrypted);
  }

  static String sigPath(Uri url) => url.path.startsWith('/algo')
      ? url.path.substring('/algo'.length) : url.path;

  static Map<String, String> headers(
    QoderAccount account, Uri url, List<int> wireBody, {
    DateTime? now, String? requestId, String? aesKey,
  }) {
    if (account.userId.isEmpty || account.token.isEmpty ||
        account.machineId.isEmpty) {
      throw const QoderAuthException('Incomplete Qoder account; sign in again.');
    }
    final key = aesKey ?? uuid().substring(0, 16);
    if (utf8.encode(key).length != 16) {
      throw const QoderAuthException('Invalid COSY AES key.');
    }
    final info = _encryptInfo({
      'uid': account.userId,
      'security_oauth_token': account.token,
      'name': account.name,
      'aid': '',
      'email': account.email,
    }, key);
    final cosyKey = wrapKey(key);
    final payload = base64Encode(utf8.encode(jsonEncode({
      'version': 'v1',
      'requestId': requestId ?? uuid(),
      'info': info,
      'cosyVersion': '1.0.0',
      'ideVersion': '',
    })));
    final time = ((now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000)
        .toString();
    final signature = md5.convert(latin1.encode(
        '$payload\n$cosyKey\n$time\n${latin1.decode(wireBody)}\n${sigPath(url)}'))
        .toString();
    final hash = md5.convert(wireBody).toString();
    return {
      'Authorization': 'Bearer COSY.$payload.$signature',
      'Cosy-Key': cosyKey,
      'Cosy-User': account.userId,
      'Cosy-Date': time,
      'Cosy-Version': '1.0.0',
      'Cosy-Machineid': account.machineId,
      'Cosy-Machinetoken': account.machineId,
      'Cosy-Machinetype': '5',
      'Cosy-Machineos': 'x86_64_windows',
      'Cosy-Clienttype': '5',
      'Cosy-Clientip': '127.0.0.1',
      'Cosy-Bodyhash': hash,
      'Cosy-Bodylength': wireBody.length.toString(),
      'Cosy-Sigpath': sigPath(url),
      'Cosy-Data-Policy': 'disagree',
      'Cosy-Organization-Id': '',
      'Cosy-Organization-Tags': '',
      'Login-Version': 'v2',
      'X-Request-Id': uuid(),
    };
  }
}
