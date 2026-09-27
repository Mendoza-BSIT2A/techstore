import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/product.dart';
import 'api_exception.dart';

/// Result of the API health check (GET api/index.php).
class ApiHealth {
  const ApiHealth({required this.message, required this.productCount});

  final String message;
  final int productCount;
}

/// Sort orders understood by GET products.php?sort=.
class ProductSort {
  ProductSort._();

  static const name = 'name';
  static const newest = 'newest';
  static const oldest = 'oldest';
  static const priceAsc = 'price_asc';
  static const priceDesc = 'price_desc';
}

/// Client for the custom REST API (backend/api/products.php or the
/// store-api Supabase Edge Function - both answer the same requests).
class ProductApiService {
  ProductApiService({http.Client? client, String Function()? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? (() => ApiConfig.baseUrl.value);

  static const _timeout = Duration(seconds: 12);
  static const _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  final http.Client _client;
  final String Function() _baseUrl;

  /// GET products.php
  Future<List<Product>> fetchProducts({
    String? search,
    String? category,
    String sort = ProductSort.name,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (category != null && category.isNotEmpty) 'category': category,
      'sort': sort,
    };
    final body = await _send(
      () => _client.get(
        _uri('products.php', query),
        headers: const {'Accept': 'application/json'},
      ),
    );
    final data = body['data'];
    if (data is! List) {
      throw const ApiException('Unexpected response: "data" should be a list.');
    }
    return data
        .whereType<Map>()
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// GET products.php?id={id}
  Future<Product> fetchProduct(int id) async {
    final body = await _send(
      () => _client.get(
        _uri('products.php', {'id': '$id'}),
        headers: const {'Accept': 'application/json'},
      ),
    );
    return _productFrom(body);
  }

  /// POST products.php
  Future<Product> createProduct(Product product) async {
    final body = await _send(
      () => _client.post(
        _uri('products.php'),
        headers: _jsonHeaders,
        body: jsonEncode(product.toJson()),
      ),
    );
    return _productFrom(body);
  }

  /// PUT products.php?id={id}
  Future<Product> updateProduct(Product product) async {
    final id = product.id;
    if (id == null) {
      throw const ApiException('Cannot update a product that has no id.');
    }
    final body = await _send(
      () => _client.put(
        _uri('products.php', {'id': '$id'}),
        headers: _jsonHeaders,
        body: jsonEncode(product.toJson()),
      ),
    );
    return _productFrom(body);
  }

  /// DELETE products.php?id={id}. Returns the server's confirmation message.
  Future<String> deleteProduct(int id) async {
    final body = await _send(
      () => _client.delete(
        _uri('products.php', {'id': '$id'}),
        headers: const {'Accept': 'application/json'},
      ),
    );
    return body['message']?.toString() ?? 'Product deleted.';
  }

  /// GET index.php, optionally against a URL that has not been saved yet.
  Future<ApiHealth> checkHealth({String? baseUrl}) async {
    final body = await _send(
      () => _client.get(
        _uri('index.php', null, baseUrl),
        headers: const {'Accept': 'application/json'},
      ),
      baseUrl: baseUrl,
    );
    return ApiHealth(
      message: body['message']?.toString() ?? 'Connected.',
      productCount: (body['product_count'] as num?)?.toInt() ?? 0,
    );
  }

  Uri _uri(String path, [Map<String, String>? query, String? baseUrl]) {
    final base = ApiConfig.normalize(baseUrl ?? _baseUrl());
    final uri = Uri.parse('$base/$path');
    return query == null || query.isEmpty
        ? uri
        : uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Product _productFrom(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is! Map) {
      throw const ApiException(
        'Unexpected response: "data" should be an object.',
      );
    }
    return Product.fromJson(Map<String, dynamic>.from(data));
  }

  /// Runs a request and turns every failure into an [ApiException].
  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request, {
    String? baseUrl,
  }) async {
    final server = ApiConfig.normalize(baseUrl ?? _baseUrl());
    http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw ApiException(
        'The server at $server took too long to respond. '
        'Check the API URL in Server Settings.',
      );
    } on FormatException {
      throw ApiException(
        '"$server" is not a valid URL. Fix it in Server Settings.',
      );
    } catch (_) {
      throw ApiException(
        'Could not reach the server at $server. '
        'Check your internet connection and the API URL in Server Settings.',
      );
    }

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      body = null;
    }

    if (body == null) {
      throw ApiException(
        'Unexpected response from the server (HTTP ${response.statusCode}). '
        'Check that the API URL points at the "api" folder.',
        statusCode: response.statusCode,
      );
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (ok && body['success'] == true) return body;

    final rawErrors = body['errors'];
    final fieldErrors = rawErrors is Map
        ? rawErrors.map((key, value) => MapEntry('$key', '$value'))
        : <String, String>{};

    throw ApiException(
      body['message']?.toString() ??
          'Request failed (HTTP ${response.statusCode}).',
      statusCode: response.statusCode,
      fieldErrors: fieldErrors,
    );
  }
}
