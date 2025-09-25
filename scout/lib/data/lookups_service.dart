import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/option_item.dart';
class InterventionOption extends OptionItem {
  final String? defaultGrantId;
  const InterventionOption(super.id, super.name, this.defaultGrantId);
}
class LookupsService {
  final _db = FirebaseFirestore.instance;

  Future<List<OptionItem>> _loadAndSort(String col, {String nameField = 'name'}) async {
    final q = await _db.collection(col)
      .where('active', isEqualTo: true)
      // no orderBy here – avoid composite index requirement
      .get();

    final items = q.docs.map((d) {
      final data = d.data();
      final name = (data[nameField] ?? '') as String;
      return OptionItem(d.id, name);
    }).toList();

    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  Future<List<OptionItem>> locations()  => _loadAndSort('locations');
  Future<List<OptionItem>> grants()     => _loadAndSort('grants');
  Future<List<OptionItem>> departments()=> _loadAndSort('departments');
  Future<List<OptionItem>> categories() => _loadAndSort('categories');
  Future<List<OptionItem>> interventions()  => _loadAndSort('interventions');
}
