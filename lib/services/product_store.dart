import 'package:flutter/foundation.dart';

import '../models/product.dart';
import 'api_exception.dart';
import 'product_api_service.dart';

/// Holds the products loaded from the custom API and keeps every screen in sync.
///
/// Every create / update / delete goes to the server first; the local list is
/// only changed after the server confirms, then listeners rebuild.
class ProductStore extends ChangeNotifier {
  ProductStore(this._api);

  final ProductApiService _api;

  List<Product> _products = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  ApiException? _error;
  int _loadRequest = 0;

  ProductApiService get api => _api;
  List<Product> get products => List.unmodifiable(_products);
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  ApiException? get error => _error;

  Product? byId(int id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  /// The inventory item linked to DummyJSON product [dummyId], if any.
  Product? byDummyId(int dummyId) {
    for (final product in _products) {
      if (product.dummyJsonId == dummyId) return product;
    }
    return null;
  }

  /// Case-insensitive, like the server's unique index on lower(name).
  Product? byName(String name) {
    final target = name.trim().toLowerCase();
    for (final product in _products) {
      if (product.name.toLowerCase() == target) return product;
    }
    return null;
  }

  /// GET all products.
  Future<void> load() async {
    // Only the most recent load may update the list, so an older, slower
    // response (e.g. from the previous server URL) can't overwrite a newer one.
    final request = ++_loadRequest;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final products = await _api.fetchProducts();
      if (request != _loadRequest) return;
      _products = _sorted(products);
      _hasLoaded = true;
    } on ApiException catch (e) {
      if (request != _loadRequest) return;
      _error = e;
    } finally {
      if (request == _loadRequest) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Forgets the current list, e.g. after switching to another server,
  /// so screens show the new server's data or error instead of stale rows.
  void reset() {
    _products = [];
    _hasLoaded = false;
    _error = null;
    notifyListeners();
  }

  /// GET one product and refresh it in the list. Removes it locally on 404.
  Future<Product> refreshOne(int id) async {
    try {
      final fresh = await _api.fetchProduct(id);
      _replace(fresh);
      return fresh;
    } on ApiException catch (e) {
      if (e.isNotFound) _removeLocal(id);
      rethrow;
    }
  }

  /// POST a new product.
  Future<Product> create(Product product) async {
    final created = await _api.createProduct(product);
    if (!_hasLoaded) {
      // The list never loaded (e.g. the server was offline at start-up):
      // fetch everything so the list shows all rows, not just the new one.
      await load();
      return created;
    }
    _products = _sorted([..._products, created]);
    notifyListeners();
    return created;
  }

  /// PUT changes to an existing product.
  Future<Product> update(Product product) async {
    try {
      final updated = await _api.updateProduct(product);
      _replace(updated);
      return updated;
    } on ApiException catch (e) {
      // Deleted elsewhere (e.g. in phpMyAdmin): drop the stale copy.
      if (e.isNotFound) _removeLocal(product.id);
      rethrow;
    }
  }

  /// DELETE a product. Returns the server's confirmation message.
  Future<String> delete(int id) async {
    try {
      final message = await _api.deleteProduct(id);
      _removeLocal(id);
      return message;
    } on ApiException catch (e) {
      if (!e.isNotFound) rethrow;
      _removeLocal(id);
      return 'This product had already been deleted.';
    }
  }

  void _removeLocal(int? id) {
    _products.removeWhere((product) => product.id == id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Dashboard statistics
  // ---------------------------------------------------------------------------

  /// Units on the shelf across every product.
  int get totalUnits =>
      _products.fold<int>(0, (sum, product) => sum + product.stock);

  /// Total value of the stock (price × units) in US dollars.
  double get inventoryValue =>
      _products.fold<double>(0, (sum, product) => sum + product.inventoryValue);

  /// Products with 1 to 5 units left, fewest first.
  List<Product> get lowStock =>
      _products.where((product) => product.isLowStock).toList()
        ..sort((a, b) => a.stock.compareTo(b.stock));

  List<Product> get outOfStock =>
      _products.where((product) => product.isOutOfStock).toList();

  int get outOfStockCount => outOfStock.length;

  /// Out-of-stock products first, then low stock - what needs reordering.
  List<Product> get stockAlerts => [...outOfStock, ...lowStock];

  /// Number of products in each category, in [Product.categories] order.
  Map<String, int> get countByCategory => {
    for (final category in Product.categories)
      category: _products
          .where((product) => product.category == category)
          .length,
  };

  List<Product> recentlyAdded([int limit = 6]) {
    final list = [..._products]
      ..sort((a, b) {
        final byDate = (b.createdAt ?? DateTime(0)).compareTo(
          a.createdAt ?? DateTime(0),
        );
        return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
      });
    return list.take(limit).toList();
  }

  void _replace(Product product) {
    final index = _products.indexWhere((item) => item.id == product.id);
    if (index == -1) {
      _products = _sorted([..._products, product]);
    } else {
      _products[index] = product;
      _products = _sorted(_products);
    }
    notifyListeners();
  }

  static List<Product> _sorted(List<Product> products) =>
      [...products]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
