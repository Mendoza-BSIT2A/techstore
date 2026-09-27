import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:techstore/services/app_services.dart';
import 'package:techstore/services/dummyjson_service.dart';
import 'package:techstore/services/product_api_service.dart';
import 'package:techstore/services/product_store.dart';

const testBaseUrl = 'http://test.local/techstore_api/api';

Map<String, dynamic> productJson({
  required int id,
  required String name,
  String category = 'Laptop',
  String brand = 'Dell',
  Object price = 999.99,
  Object stock = 10,
  String description = 'A great product.',
  String? imageUrl,
  int? dummyId,
  String createdAt = '2026-09-01 10:00:00',
}) => {
  'id': id,
  'name': name,
  'category': category,
  'brand': brand,
  'price': price,
  'stock': stock,
  'description': description,
  'image_url': imageUrl,
  'dummyjson_id': dummyId,
  'created_at': createdAt,
  'updated_at': createdAt,
};

http.Response jsonResponse(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// In-memory stand-in for backend/api/products.php.
class FakeProductBackend {
  FakeProductBackend([List<Map<String, dynamic>>? seed])
    : rows = [...?seed],
      _nextId = (seed?.length ?? 0) + 1;

  final List<Map<String, dynamic>> rows;
  final List<http.Request> requests = [];
  int _nextId;

  /// When set, the next POST/PUT answers 422 with these field errors.
  Map<String, String>? nextValidationErrors;

  late final MockClient client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final id = int.tryParse(request.url.queryParameters['id'] ?? '');

    if (request.url.path.endsWith('index.php')) {
      return jsonResponse({
        'success': true,
        'message': 'TechStore API is running.',
        'product_count': rows.length,
      }, 200);
    }

    switch (request.method) {
      case 'GET':
        if (id == null) {
          return jsonResponse({
            'success': true,
            'count': rows.length,
            'data': rows,
          }, 200);
        }
        final row = _find(id);
        return row == null
            ? jsonResponse({
                'success': false,
                'message': 'Product with id $id was not found.',
              }, 404)
            : jsonResponse({'success': true, 'data': row}, 200);

      case 'POST':
      case 'PUT':
        final errors = nextValidationErrors;
        if (errors != null) {
          nextValidationErrors = null;
          return jsonResponse({
            'success': false,
            'message': 'Please fix the highlighted fields.',
            'errors': errors,
          }, 422);
        }
        final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        if (request.method == 'POST') {
          final row = {
            ...body,
            'id': _nextId++,
            'created_at': '2026-09-26 12:00:00',
            'updated_at': '2026-09-26 12:00:00',
          };
          rows.add(row);
          return jsonResponse({
            'success': true,
            'message': 'Product created.',
            'data': row,
          }, 201);
        }
        final existing = _find(id!);
        if (existing == null) {
          return jsonResponse({
            'success': false,
            'message': 'Product with id $id was not found.',
          }, 404);
        }
        existing.addAll(body);
        return jsonResponse({
          'success': true,
          'message': 'Product updated.',
          'data': existing,
        }, 200);

      case 'DELETE':
        final row = _find(id!);
        if (row == null) {
          return jsonResponse({
            'success': false,
            'message': 'Product with id $id was not found.',
          }, 404);
        }
        rows.remove(row);
        return jsonResponse({
          'success': true,
          'message': 'Product "${row['name']}" deleted.',
          'data': row,
        }, 200);
    }
    return jsonResponse({
      'success': false,
      'message': 'Method not allowed.',
    }, 405);
  }

  Map<String, dynamic>? _find(int id) {
    for (final row in rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }
}

Map<String, dynamic> dummyProductJson({
  required int id,
  required String title,
  required String category,
  double price = 99.99,
  String? brand,
  double discount = 10.5,
  double rating = 4.5,
  int stock = 20,
}) => {
  'id': id,
  'title': title,
  'description': '$title from the fake DummyJSON API.',
  'category': category,
  'price': price,
  'discountPercentage': discount,
  'rating': rating,
  'stock': stock,
  // DummyJSON leaves out "brand" for some products.
  if (brand != null) 'brand': brand,
  'sku': 'SKU-$id',
  'warrantyInformation': '1 year warranty',
  'shippingInformation': 'Ships in 1 week',
  'availabilityStatus': 'In Stock',
  'images': [
    'https://cdn.dummyjson.com/product-images/$id/1.webp',
    'https://cdn.dummyjson.com/product-images/$id/2.webp',
  ],
  'thumbnail': 'https://cdn.dummyjson.com/product-images/$id/thumbnail.webp',
};

/// Canned DummyJSON catalogue: tech products plus one non-tech product that
/// the app must filter out of search results.
final fakeDummyProducts = [
  dummyProductJson(
    id: 78,
    title: 'Apple MacBook Pro 14 Inch Space Grey',
    category: 'laptops',
    price: 1999.99,
    brand: 'Apple',
  ),
  dummyProductJson(
    id: 79,
    title: 'Asus Zenbook Pro Dual Screen Laptop',
    category: 'laptops',
    price: 1799.99,
    brand: 'Asus',
  ),
  dummyProductJson(
    id: 100,
    title: 'Apple Airpods',
    category: 'mobile-accessories',
    price: 129.99,
    brand: 'Apple',
  ),
  dummyProductJson(
    id: 107,
    title: 'Beats Flex Wireless Earphones',
    category: 'mobile-accessories',
    price: 49.99,
  ),
  dummyProductJson(
    id: 159,
    title: 'iPad Mini 2021 Starlight',
    category: 'tablets',
    price: 499.99,
    brand: 'Apple',
  ),
  dummyProductJson(
    id: 121,
    title: 'iPhone 5s',
    category: 'smartphones',
    price: 199.99,
    brand: 'Apple',
  ),
  dummyProductJson(
    id: 1,
    title: 'Essence Mascara Lash Princess',
    category: 'beauty',
    price: 9.99,
    brand: 'Essence',
  ),
];

/// Canned DummyJSON API responses. Every request is added to [log] when given.
MockClient fakeDummyJsonClient({List<http.Request>? log}) => MockClient((
  request,
) async {
  log?.add(request);
  final path = request.url.path;

  Map<String, dynamic> list(List<Map<String, dynamic>> products) => {
    'products': products,
    'total': products.length,
    'skip': 0,
    'limit': products.length,
  };

  final category = RegExp(r'^/products/category/(.+)$').firstMatch(path);
  if (category != null) {
    final slug = Uri.decodeComponent(category.group(1)!);
    return jsonResponse(
      list(fakeDummyProducts.where((p) => p['category'] == slug).toList()),
      200,
    );
  }

  if (path == '/products/search') {
    final query = (request.url.queryParameters['q'] ?? '').toLowerCase();
    return jsonResponse(
      list(
        fakeDummyProducts
            .where(
              (p) => '${p['title']} ${p['description']}'.toLowerCase().contains(
                query,
              ),
            )
            .toList(),
      ),
      200,
    );
  }

  final one = RegExp(r'^/products/(\d+)$').firstMatch(path);
  if (one != null) {
    final id = int.parse(one.group(1)!);
    for (final product in fakeDummyProducts) {
      if (product['id'] == id) return jsonResponse(product, 200);
    }
    return jsonResponse({'message': "Product with id '$id' not found"}, 404);
  }

  return jsonResponse({'message': 'Not found'}, 404);
});

/// Points [AppServices] at fakes and returns the fake backend.
FakeProductBackend installFakeServices([List<Map<String, dynamic>>? seed]) {
  final backend = FakeProductBackend(seed);
  AppServices.productStore = ProductStore(
    ProductApiService(client: backend.client, baseUrl: () => testBaseUrl),
  );
  AppServices.dummyJson = DummyJsonService(
    client: fakeDummyJsonClient(),
    random: Random(1),
  );
  return backend;
}
