import 'package:web/web.dart' as web;

void downloadDataUrl(String dataUrl, String fileName) {
  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = fileName;
  anchor.click();
}
