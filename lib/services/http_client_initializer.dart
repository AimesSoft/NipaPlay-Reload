import 'certificate_trust_service.dart';

// 分平台导入：IO 使用 HttpOverrides，Web 使用空实现
import 'http_overrides_io.dart' if (dart.library.html) 'http_overrides_web.dart';

class HttpClientInitializer {
  static bool _installed = false;

  static Future<void> install() async {
    if (_installed) return;

    // 加载用户保存的证书信任规则
    await CertificateTrustService.instance.initialize();

    // 安装平台对应的 HttpOverrides（Web 无操作）
    installNipaHttpOverrides();

    _installed = true;
  }
}
