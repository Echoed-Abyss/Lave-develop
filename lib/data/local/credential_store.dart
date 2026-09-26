import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/bot_profile.dart';

/// 机器人凭证的安全存储。
///
/// **所有密钥只走这里**：AppSecret / BotToken 绝不写入普通 JSON 文件，
/// 因为那些文件在设备上明文可见（Android 的 app 私有目录在 root 或
/// 备份提取场景下可读）。
///
/// 采用 `flutter_secure_storage`：iOS 走 Keychain，Android 走
/// KeyStore 包裹的加密存储（v10+ 默认 RSA-OAEP + AES-GCM）。
class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Android 侧显式使用默认非生物识别方案：
              // 生物识别会在冷启动时弹窗，对「后台自动重连」是致命的。
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                // first_unlock：设备首次解锁后即可读取。
                // 用默认的 unlocked 会导致开机后未解锁时无法自动重连。
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  static const String _secretPrefix = 'bot_secret_';
  static const String _tokenPrefix = 'bot_token_';
  static const String _schemePrefix = 'bot_scheme_';

  /// 保存凭证（AppID 作为键的一部分）。
  Future<void> save(BotCredential credential) async {
    try {
      final id = credential.appId;
      final secret = credential.appSecret;
      final token = credential.botToken;

      if (secret != null && secret.isNotEmpty) {
        await _storage.write(key: '$_secretPrefix$id', value: secret);
      } else {
        await _storage.delete(key: '$_secretPrefix$id');
      }

      if (token != null && token.isNotEmpty) {
        await _storage.write(key: '$_tokenPrefix$id', value: token);
      } else {
        await _storage.delete(key: '$_tokenPrefix$id');
      }

      await _storage.write(
        key: '$_schemePrefix$id',
        value: credential.tokenScheme.name,
      );
    } catch (error, stack) {
      AppLogger.error('保存凭证失败',
          error: error, stackTrace: stack, tag: 'credential');
      rethrow;
    }
  }

  /// 读取凭证。不存在时返回只含 AppID 的空凭证。
  Future<BotCredential> load(String appId) async {
    try {
      final secret = await _storage.read(key: '$_secretPrefix$appId');
      final token = await _storage.read(key: '$_tokenPrefix$appId');
      final scheme = await _storage.read(key: '$_schemePrefix$appId');
      return BotCredential(
        appId: appId,
        appSecret: secret,
        botToken: token,
        tokenScheme: TokenScheme.fromName(scheme),
      );
    } catch (error, stack) {
      // 读取失败（例如密钥损坏）时返回空凭证而不是让整个页面崩溃，
      // 界面会提示「凭证无效或已过期」，用户重新填写即可恢复。
      AppLogger.error('读取凭证失败，已按空凭证处理',
          error: error, stackTrace: stack, tag: 'credential');
      return BotCredential(appId: appId);
    }
  }

  /// 删除凭证。
  Future<void> delete(String appId) async {
    try {
      await _storage.delete(key: '$_secretPrefix$appId');
      await _storage.delete(key: '$_tokenPrefix$appId');
      await _storage.delete(key: '$_schemePrefix$appId');
    } catch (error) {
      AppLogger.warn('删除凭证失败：$error', tag: 'credential');
    }
  }

  /// 是否已保存过密钥（用于界面上显示「已配置 / 未配置」）。
  Future<bool> hasSecret(String appId) async {
    try {
      final secret = await _storage.read(key: '$_secretPrefix$appId');
      return secret != null && secret.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
