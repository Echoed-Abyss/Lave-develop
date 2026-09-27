/// 应用元信息。
///
/// 版本号在此单独声明，是因为界面展示需要它而 Flutter 不提供
/// 读取 `pubspec.yaml` 的官方途径（引入 `package_info_plus` 会增加
/// 一个原生依赖，对一处静态文本并不划算）。
///
/// **改动 `pubspec.yaml` 的 `version` 时，这里必须同步修改。**
abstract final class AppInfo {
  /// 应用名。
  static const String name = 'Lave';

  /// 当前版本（与 pubspec.yaml 的 version 保持一致）。
  static const String version = '1.0.0+1';

  /// 作者。
  static const String author = 'BaiXuan';
}
