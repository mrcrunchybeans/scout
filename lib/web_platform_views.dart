// Web-only platform view registration for budget iframe
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:js' as js;

/// Register the budget iframe platform view
/// This is only called on web platform
void registerBudgetIframe() {
  try {
    // Access flutter namespace from window object
    final flutterValue = js.context['flutter'];
    if (flutterValue != null) {
      // Try to get platformViewRegistry from the flutter web runtime
      // ignore: avoid_dynamic_calls
      final registry = js_util.getProperty(flutterValue, 'platformViewRegistry');
      if (registry != null) {
        // ignore: avoid_dynamic_calls
        js_util.callMethod(registry, 'registerViewFactory', [
          'budget-iframe',
          js.allowInterop((int viewId) {
            final iframe = html.IFrameElement();
            iframe.src = 'https://budget.scoutapp.org';
            iframe.style.border = 'none';
            iframe.allow = 'clipboard-write';
            iframe.width = '100%';
            iframe.height = '100%';
            return iframe;
          }),
        ]);
      }
    }
  } catch (e) {
    // Silently fail if platformViewRegistry is not available
    // The HtmlElementView will still work if manually registered
  }
}

