/// A product record (laptop, part or accessory) stored in the custom database.
class Product {
  const Product({
    this.id,
    required this.name,
    required this.category,
    this.brand = '',
    required this.price,
    required this.stock,
    this.description = '',
    this.imageUrl,
    this.dummyJsonId,
    this.createdAt,
    this.updatedAt,
  });

  /// Must match PRODUCT_CATEGORIES in backend/api/helpers.php.
  static const categories = ['Laptop', 'Parts', 'Accessories'];

  /// Same limits as the server-side validation.
  static const minPrice = 0.01;
  static const maxPrice = 1000000.0;
  static const maxStock = 100000;

  /// Stock levels from 1 to this number count as "low stock".
  static const lowStockLimit = 5;

  final int? id;
  final String name;
  final String category;
  final String brand;

  /// Price in US dollars, at most two decimals.
  final double price;

  /// Units available in the shop.
  final int stock;
  final String description;
  final String? imageUrl;

  /// Id of the linked product on dummyjson.com, if any.
  final int? dummyJsonId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: _toInt(json['id']),
      name: _toStr(json['name']),
      category: _toStr(json['category']),
      brand: _toStr(json['brand']),
      price: _toDouble(json['price']) ?? 0,
      stock: _toInt(json['stock']) ?? 0,
      description: _toStr(json['description']),
      imageUrl: _toNullableStr(json['image_url']),
      dummyJsonId: _toInt(json['dummyjson_id']),
      createdAt: DateTime.tryParse(_toStr(json['created_at']))?.toLocal(),
      updatedAt: DateTime.tryParse(_toStr(json['updated_at']))?.toLocal(),
    );
  }

  /// Request body for POST / PUT. The id and timestamps are managed by the server.
  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'brand': brand,
    // Rounded so binary floating point never sends a third decimal.
    'price': double.parse(price.toStringAsFixed(2)),
    'stock': stock,
    'description': description,
    'image_url': imageUrl ?? '',
    'dummyjson_id': dummyJsonId,
  };

  Product copyWith({String? imageUrl, int? dummyJsonId}) => Product(
    id: id,
    name: name,
    category: category,
    brand: brand,
    price: price,
    stock: stock,
    description: description,
    imageUrl: imageUrl ?? this.imageUrl,
    dummyJsonId: dummyJsonId ?? this.dummyJsonId,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  bool get isOutOfStock => stock <= 0;

  bool get isLowStock => stock >= 1 && stock <= lowStockLimit;

  /// "Out of stock", "Low stock · 3 left" or "24 in stock".
  String get stockLabel {
    if (isOutOfStock) return 'Out of stock';
    if (isLowStock) return 'Low stock · $stock left';
    return '$stock in stock';
  }

  /// Value of the units on the shelf (price × stock).
  double get inventoryValue => price * stock;

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  static int? _toInt(dynamic value) {
    if (value is bool) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// Prices arrive as JSON numbers, but MySQL DECIMAL columns may be sent as
  /// strings such as "1999.99", so both are accepted.
  static double? _toDouble(dynamic value) {
    if (value is bool) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static String _toStr(dynamic value) => value == null ? '' : value.toString();

  static String? _toNullableStr(dynamic value) {
    final text = _toStr(value).trim();
    return text.isEmpty ? null : text;
  }
}
