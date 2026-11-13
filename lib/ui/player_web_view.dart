import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/download_service.dart';

/// Абстракция над WebView.
///
/// Зачем: настоящий `InAppWebView` в widget-тестах недоступен (нет нативной
/// платформы), а поведение экрана проверить хочется. Поэтому экран плеера
/// принимает любую реализацию этого интерфейса.
abstract class PlayerWebView {
  Widget build({
    required String url,
    required ValueChanged<String> onResource,
    required VoidCallback onLoadStart,
    required VoidCallback onLoadStop,
    required ValueChanged<PlayerWebViewHandle> onReady,
  });
}

/// То, что нужно экрану от контроллера WebView.
class PlayerWebViewHandle {
  const PlayerWebViewHandle({this.reload});

  final VoidCallback? reload;

  static const PlayerWebViewHandle none = PlayerWebViewHandle();
}

/// Боевая реализация на flutter_inappwebview.
class RealPlayerWebView implements PlayerWebView {
  const RealPlayerWebView();

  @override
  Widget build({
    required String url,
    required ValueChanged<String> onResource,
    required VoidCallback onLoadStart,
    required VoidCallback onLoadStop,
    required ValueChanged<PlayerWebViewHandle> onReady,
  }) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        useOnLoadResource: true,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        userAgent: DownloadService.userAgent,
      ),
      onWebViewCreated: (controller) {
        onReady(PlayerWebViewHandle(reload: controller.reload));
      },
      onLoadStart: (_, __) => onLoadStart(),
      onLoadStop: (_, __) => onLoadStop(),
      onLoadResource: (controller, resource) =>
          onResource(resource.url.toString()),
    );
  }
}
