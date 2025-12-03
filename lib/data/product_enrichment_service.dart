import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scout/utils/audit.dart';
import 'package:scout/utils/operator_store.dart';

class ProductEnrichmentService {
  static const _openFoodFactsBase = 'https://world.openfoodfacts.org/api/v0/product';
  static const _upcDatabaseBase = 'https://api.upcdatabase.org/product';
  static const _upcApiKey = '30BCAE6307A2AF6171693CBF1717457A';

  static Future<Map<String, dynamic>?> fetchProductInfo(String barcode) async {
    // First, check cache
    final cached = await FirebaseFirestore.instance.collection('catalog').doc(barcode).get();
    if (cached.exists) {
      return cached.data();
    }

    // Try OpenFoodFacts first
    final info = await _fetchFromOpenFoodFacts(barcode);
    if (info != null) return info;

    // Fallback to UPCDatabase
    final upcInfo = await _fetchFromUPCDatabase(barcode);
    if (upcInfo != null) return upcInfo;

    // If not found anywhere, cache empty
    await FirebaseFirestore.instance.collection('catalog').doc(barcode).set({
      'name': null,
      'source': 'not_found',
      'fetchedAt': FieldValue.serverTimestamp(),
    });

    return null;
  }

  static Future<Map<String, dynamic>?> _fetchFromOpenFoodFacts(String barcode) async {
    final url = '$_openFoodFactsBase/$barcode.json';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];
          final info = {
            'name': product['product_name'] ?? product['product_name_en'] ?? 'Unknown Product',
            'brand': product['brands'] ?? '',
            'category': product['categories'] ?? '',
            'source': 'openfoodfacts',
            'fetchedAt': FieldValue.serverTimestamp(),
          };
          // Cache it
          await FirebaseFirestore.instance.collection('catalog').doc(barcode).set(info);
          return info;
        }
      }
    } catch (e) {
      // Ignore errors
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _fetchFromUPCDatabase(String barcode) async {
    final url = '$_upcDatabaseBase/$barcode/$_upcApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['product'] != null) {
          final product = data['product'];
          final info = {
            'name': product['title'] ?? 'Unknown Product',
            'brand': product['brand'] ?? '',
            'category': product['category'] ?? '',
            'source': 'upcdatabase',
            'fetchedAt': FieldValue.serverTimestamp(),
          };
          // Cache it
          await FirebaseFirestore.instance.collection('catalog').doc(barcode).set(info);
          return info;
        }
      }
    } catch (e) {
      // Ignore errors
    }
    return null;
  }

  static Future<String?> createItemWithEnrichment(String barcode, FirebaseFirestore db) async {
    final info = await fetchProductInfo(barcode);
    if (info == null || info['name'] == null) return null;

    final ref = db.collection('items').doc();
    await ref.set({
      'name': info['name'],
      'category': info['category'] ?? '',
      'baseUnit': 'each',
      'unit': 'each',
      'qtyOnHand': 0,
      'minQty': 0,
      'maxQty': null,
      'useType': 'both',
      'grantId': null,
      'departmentId': null,
      'homeLocationId': null,
      'barcode': barcode,
      'barcodes': [barcode],
      'expiresAt': null,
      'lastUsedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'operatorName': OperatorStore.name.value,
    });

    await Audit.log('item.create', {
      'itemId': ref.id,
      'name': info['name'],
      'barcode': barcode,
      'source': 'auto_enriched',
    });

    return ref.id;
  }
}
