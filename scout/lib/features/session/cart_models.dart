class CartLine {
  final String itemId;
  final String itemName;
  final String baseUnit;
  final String? lotId;        // optional, if using lots
  final num initialQty;
  final num? endQty;          // null until closing

  CartLine({
    required this.itemId,
    required this.itemName,
    required this.baseUnit,
    this.lotId,
    required this.initialQty,
    this.endQty,
  });

  num get usedQty => (endQty == null) ? 0 : (initialQty - (endQty ?? 0)).clamp(0, double.infinity);

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'itemName': itemName,
    'baseUnit': baseUnit,
    'lotId': lotId,
    'initialQty': initialQty,
    'endQty': endQty,
  };

  static CartLine fromMap(Map<String, dynamic> m) => CartLine(
    itemId: m['itemId'] as String,
    itemName: (m['itemName'] ?? 'Unnamed') as String,
    baseUnit: (m['baseUnit'] ?? 'each') as String,
    lotId: m['lotId'] as String?,
    initialQty: (m['initialQty'] ?? 0) as num,
    endQty: m['endQty'] as num?,
  );
}
