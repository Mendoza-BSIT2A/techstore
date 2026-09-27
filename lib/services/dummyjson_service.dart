import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/dummy_product.dart';
import 'api_exception.dart';

/// Client for the third-party DummyJSON API (https://dummyjson.com/docs/products).
///
/// DummyJSON sells everything from mascara to motorcycles; this app only uses
/// the tech categories in [techCategories].
class DummyJsonService {
  DummyJsonService({http.Client? client, Random? random})
    : _client = client ?? http.Client(),
      _random = random ?? Random();

  static const _timeout = Duration(seconds: 12);

  /// DummyJSON category slugs shown in the app, in display order.
  static const techCategories = [
    'laptops',
    'mobile-accessories',
    'tablets',
    'smartphones',
  ];

  /// The Deal of the Day is picked from these categories.
  static const dealCategories = ['laptops', 'mobile-accessories'];

  static const _categoryNames = {
    'laptops': 'Laptops',
    'mobile-accessories': 'Accessories',
    'tablets': 'Tablets',
    'smartphones': 'Smartphones',
  };

  final http.Client _client;
  final Random _random;
  final Map<String, Future<List<DummyProduct>>> _categories = {};

  /// GET /products/category/{category}?limit=0, cached per category so
  /// switching chips or scrolling does not refetch.
  Future<List<DummyProduct>> productsInCategory(
    String category, {
    bool forceRefresh = false,
  }) {
    final cached = _categories[category];
    if (cached != null && !forceRefresh) return cached;

    final future = _fetchList(
      '/products/category/${Uri.encodeComponent(category)}',
      const {'limit': '0'},
    );
    _categories[category] = future;
    // Forget failures so the next attempt retries.
    future.catchError((Object _) {
      if (identical(_categories[category], future)) {
        _categories.remove(category);
      }
      return const <DummyProduct>[];
    });
    return future;
  }

  /// Every product in [techCategories] (uses the per-category cache).
  Future<List<DummyProduct>> allTechProducts({
    bool forceRefresh = false,
  }) async {
    final lists = await Future.wait([
      for (final category in techCategories)
        productsInCategory(category, forceRefresh: forceRefresh),
    ]);
    return [for (final list in lists) ...list];
  }

  /// GET /products/search?q={query}&limit=0, keeping only tech products.
  Future<List<DummyProduct>> search(String query) async {
    final results = await _fetchList('/products/search', {
      'q': query.trim(),
      'limit': '0',
    });
    return results
        .where((product) => techCategories.contains(product.category))
        .toList();
  }

  /// GET /products/{id}
  Future<DummyProduct> product(int id) async {
    final body = await _get('/products/$id');
    if (body['id'] == null) throw _unexpected();
    return DummyProduct.fromJson(body);
  }

  /// A random laptop or mobile accessory for the dashboard's Deal of the Day.
  /// [excludeId] avoids showing the same product twice in a row.
  Future<DummyProduct> randomDeal({int? excludeId}) async {
    final lists = await Future.wait([
      for (final category in dealCategories) productsInCategory(category),
    ]);
    final all = [for (final list in lists) ...list];
    if (all.isEmpty) {
      throw const ApiException('DummyJSON has no products to show right now.');
    }
    final pool = all.length > 1
        ? all.where((product) => product.id != excludeId).toList()
        : all;
    return pool[_random.nextInt(pool.length)];
  }

  Future<List<DummyProduct>> _fetchList(
    String path, [
    Map<String, String>? query,
  ]) async {
    final body = await _get(path, query);
    final products = body['products'];
    if (products is! List) throw _unexpected();
    return products
        .whereType<Map>()
        .map((item) => DummyProduct.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    var uri = Uri.parse('${ApiConfig.dummyJsonBaseUrl}$path');
    if (query != null) uri = uri.replace(queryParameters: query);

    http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('DummyJSON took too long to respond.');
    } catch (_) {
      throw const ApiException(
        'Could not reach DummyJSON. Check your internet connection.',
      );
    }

    dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiException(
        'DummyJSON returned an unreadable response (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode == 200 && body is Map) {
      return Map<String, dynamic>.from(body);
    }

    final message = body is Map ? body['message']?.toString() : null;
    throw ApiException(
      message ?? 'DummyJSON error (HTTP ${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }

  ApiException _unexpected() =>
      const ApiException('DummyJSON returned data in an unexpected format.');

  // ---------------------------------------------------------------------------
  // Naming helpers
  // ---------------------------------------------------------------------------

  /// `mobile-accessories` -> `Accessories`, `home-decoration` -> `Home Decoration`.
  static String categoryLabel(String category) =>
      _categoryNames[category] ??
      category
          .split('-')
          .where((word) => word.isNotEmpty)
          .map((word) => word[0].toUpperCase() + word.substring(1))
          .join(' ');

  /// Shop category (Product.categories) used when importing from [category].
  static String categoryToShop(String category) =>
      DummyProduct.shopCategoryFor(category);
}
