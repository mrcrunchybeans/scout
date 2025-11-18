import 'package:web/web.dart' as web;

/// Web implementation that triggers a download via an anchor element.
void downloadDataUrl(String dataUrl, String fileName) {
  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = fileName;
  anchor.click();
}
