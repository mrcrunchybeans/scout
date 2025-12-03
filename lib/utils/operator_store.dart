import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class OperatorStore {
  static final ValueNotifier<String?> name = ValueNotifier<String?>(null);

  static Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    name.value = sp.getString('operator_name');
  }

  static Future<void> set(String? v) async {
    final sp = await SharedPreferences.getInstance();
    if (v == null || v.isEmpty) {
      await sp.remove('operator_name');
      name.value = null;
    } else {
      await sp.setString('operator_name', v);
      name.value = v;
    }
  }
}
