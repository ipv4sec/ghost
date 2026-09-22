/// 应用配置
///
/// `appId`: 115 开放平台的 client_id（AppID）。
/// 在 https://open.115.com 申请应用后填写到这里。
/// 留空时 App 内"我的 → AppID 设置"可临时填写（仅本机保存）。
class AppConfig {
  /// TODO(user): 在此填入你的 115 开放平台 AppID（client_id）
  static const String appId = '100195647';

  /// 文件显示的最小大小（字节），小于此值的文件不显示；文件夹不受限。
  /// 512 MB = 512 * 1024 * 1024
  static const int minFileSize = 512 * 1024 * 1024;

  /// 115 开放平台 API 域名
  static const String passportApi = 'https://passportapi.115.com';
  static const String qrcodeApi = 'https://qrcodeapi.115.com';
  static const String proApi = 'https://proapi.115.com';
}
