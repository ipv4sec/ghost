import 'dart:convert';
import 'dart:math';

/// PKCE 工具：生成 code_verifier 与 code_challenge
class Pkce {
  Pkce._();

  /// 生成随机 code_verifier（64 字符，A-Za-z0-9-._~，满足 43-128 位要求）
  static String generateVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(64, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// 由 code_verifier 计算 code_challenge：url_safe(base64(sha256(verifier)))，去除 = 填充
  /// sha256 由调用方传入（避免在此 import crypto，保持纯 Dart 可测试）
  static String challengeFrom(List<int> digestBytes) {
    final b64 = base64Encode(digestBytes);
    return b64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  }
}
