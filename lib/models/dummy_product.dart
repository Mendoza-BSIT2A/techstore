/// A product from the third-party DummyJSON API (https://dummyjson.com/docs/products).
class DummyProduct {
  const DummyProduct({
    required this.id,
    required this.title,
    this.description = '',
    this.category = '',
    this.price = 0,
    this.discountPercentage = 0,
    this.rating = 0,
    this.stock = 0,
    this.brand = '',
    this.sku = '',
    this.warrantyInformation = '',
    this.shippingInformation = '',
    this.availabilityStatus = '',
    this.images = const [],
    this.thumbnail = '',
  });

  /// Which shop category (see Product.categories) each DummyJSON category
  /// becomes when a product is imported into the inventory.
  static const _shopCategories = {
    'laptops': 'Laptop',
    'mobile-accessories': 'Accessories',
    'tablets': 'Accessories',
    'smartphones': 'Accessories',
  };

  final int id;
  final String title;
  final String description;

  /// DummyJSON category slug, e.g. `laptops` or `mobile-accessories`.
  final String category;
  final double price;
  final double discountPercentage;
  final double rating;
  final int stock;

  /// Empty when DummyJSON does not list a brand.
  final String brand;
  final String sku;
  final String warrantyInformation;
  final String shippingInformation;
  final String availabilityStatus;
  final List<String> images;
  final String thumbnail;

  factory DummyProduct.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'];
    return DummyProduct(
      id: _toInt(json['id']) ?? 0,
      title: _toStr(json['title']),
      description: _toStr(json['description']),
      category: _toStr(json['category']),
      price: _toDouble(json['price']),
      discountPercentage: _toDouble(json['discountPercentage']),
      rating: _toDouble(json['rating']),
      stock: _toInt(json['stock']) ?? 0,
      brand: _toStr(json['brand']),
      sku: _toStr(json['sku']),
      warrantyInformation: _toStr(json['warrantyInformation']),
      shippingInformation: _toStr(json['shippingInformation']),
      availabilityStatus: _toStr(json['availabilityStatus']),
      images: rawImages is List
          ? rawImages
                .map((url) => _toStr(url).trim())
                .where((url) => url.isNotEmpty)
                .toList()
          : const [],
      thumbnail: _toStr(json['thumbnail']).trim(),
    );
  }

  /// Shop category for [category]; unknown tech categories count as accessories.
  static String shopCategoryFor(String category) =>
      _shopCategories[category] ?? 'Accessories';

  String get shopCategory => shopCategoryFor(category);

  /// Price after the DummyJSON discount, rounded to cents.
  double get discountedPrice =>
      (price * (1 - discountPercentage / 100) * 100).round() / 100;

  bool get hasDiscount => discountPercentage >= 0.5;

  /// The thumbnail, else the first photo, else null.
  String? get coverImage {
    if (thumbnail.isNotEmpty) return thumbnail;
    return images.isEmpty ? null : images.first;
  }

  /// Thumbnail plus every photo, without duplicates.
  List<String> get allImages =>
      {if (thumbnail.isNotEmpty) thumbnail, ...images}.toList();

  static int? _toInt(dynamic value) {
    if (value is bool) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static String _toStr(dynamic value) => value == null ? '' : value.toString();
}
