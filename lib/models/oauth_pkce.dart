/// Reusable PKCE / state primitives for desktop OAuth.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class OAuthPkce {
  const OAuthPkce(this.verifier, this.challenge);

  factory OAuthPkce.generate([Random? random]) {
    final source = random ?? Random.secure();
    final verifier = base64Url
        .encode([for (var i = 0; i < 64; i++) source.nextInt(256)])
        .replaceAll('=', '');
    return OAuthPkce(verifier, challengeOf(verifier));
  }

  final String verifier;
  final String challenge;

  static String challengeOf(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');
}

String oauthRandomState([Random? random]) {
  final source = random ?? Random.secure();
  return base64Url
      .encode([for (var i = 0; i < 32; i++) source.nextInt(256)])
      .replaceAll('=', '');
}
