import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:techstore/models/dummy_product.dart';
import 'package:techstore/models/product.dart';
import 'package:techstore/services/api_exception.dart';
import 'package:techstore/services/dummyjson_service.dart';
import 'package:techstore/services/product_api_service.dart';
import 'package:techstore/services/product_store.dart';
import 'package:techstore/utils/format.dart';

import 'support/fakes.dart';

const _ssd = Product(
  name: 'Samsung 980 PRO 1TB NVMe SSD',
  category: 'Parts',
  brand: 'Samsung',
  price: 89.99,
  stock: 18,
);

void main() {
  group('Product model', () {
    test('parses API JSON, including numbers sent as strings', () {
      final product = Product.fromJson({
        ...productJson(
          id: 3,
          name: 'Dell XPS 13 9300',
          dummyId: 82,
          imageUrl: 'https://x/y.webp',
        ),
        'id': '3',
        'price': '1499.99',
        'stock': '74',
      });

      expect(product.id, 3);
      expect(product.price, 1499.99);
      expect(product.stock, 74);
      expect(product.dummyJsonId, 82);
      expect(product.inventoryValue, closeTo(110999.26, 0.001));
      expect(product.stockLabel, '74 in stock');
      expect(product.createdAt, DateTime(2026, 9, 1, 10));
    });

    test('knows low and out-of-stock levels', () {
      Product withStock(int stock) =>
          Product.fromJson(productJson(id: 1, name: 'X', stock: stock));

      expect(withStock(0).isOutOfStock, isTrue);
      expect(withStock(0).isLowStock, isFalse);
      expect(withStock(0).stockLabel, 'Out of stock');
      expect(withStock(1).isLowStock, isTrue);
      expect(withStock(5).isLowStock, isTrue);
      expect(withStock(5).stockLabel, 'Low stock · 5 left');
      expect(withStock(6).isLowStock, isFalse);
      expect(withStock(6).isOutOfStock, isFalse);
    });

    test('toJson sends numbers and empty links, never the id', () {
      final json = _ssd.toJson();
      expect(json, containsPair('price', 89.99));
      expect(json, containsPair('stock', 18));
      expect(json, containsPair('image_url', ''));
      expect(json, containsPair('dummyjson_id', null));
      expect(json.containsKey('id'), isFalse);
      expect(jsonEncode(json), contains('"price":89.99'));
    });
  });

  group('ProductApiService', () {
    test('sends each CRUD request with the right method and URL', () async {
      final backend = FakeProductBackend([
        productJson(id: 1, name: 'Lenovo Yoga 920'),
      ]);
      final api = ProductApiService(
        client: backend.client,
        baseUrl: () => '$testBaseUrl/',
      );

      final list = await api.fetchProducts(
        search: 'yoga',
        category: 'Laptop',
        sort: ProductSort.priceAsc,
      );
      expect(list.single.name, 'Lenovo Yoga 920');
      expect(
        backend.requests.last.url.toString(),
        '$testBaseUrl/products.php?search=yoga&category=Laptop&sort=price_asc',
      );

      final created = await api.createProduct(_ssd);
      expect(created.id, 2);
      expect(created.price, 89.99);
      expect(backend.requests.last.method, 'POST');
      expect(
        backend.requests.last.headers['Content-Type'],
        startsWith('application/json'),
      );
      expect(jsonDecode(backend.requests.last.body)['name'], _ssd.name);

      final fetched = await api.fetchProduct(2);
      expect(fetched.name, _ssd.name);
      expect(backend.requests.last.url.queryParameters['id'], '2');

      final updated = await api.updateProduct(
        Product.fromJson({...backend.rows.last, 'stock': 0}),
      );
      expect(updated.stock, 0);
      expect(backend.requests.last.method, 'PUT');
      expect(backend.requests.last.url.queryParameters['id'], '2');

      final message = await api.deleteProduct(2);
      expect(message, 'Product "${_ssd.name}" deleted.');
      expect(backend.requests.last.method, 'DELETE');
      expect(backend.rows, hasLength(1));

      final health = await api.checkHealth();
      expect(health.message, 'TechStore API is running.');
      expect(health.productCount, 1);
    });

    test('turns a 422 response into field errors', () async {
      final backend = FakeProductBackend()
        ..nextValidationErrors = {
          'name': 'A product with this name already exists.',
          'price':
              'Price must be a number from 0.01 to 1,000,000 with at most 2 decimals.',
        };
      final api = ProductApiService(
        client: backend.client,
        baseUrl: () => testBaseUrl,
      );

      await expectLater(
        api.createProduct(_ssd),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.isValidation, 'isValidation', isTrue)
              .having(
                (e) => e.fieldErrors['name'],
                'name error',
                contains('already exists'),
              )
              .having(
                (e) => e.fieldErrors['price'],
                'price error',
                contains('at most 2 decimals'),
              ),
        ),
      );
    });

    test(
      'reports 404, HTML responses and unreachable servers clearly',
      () async {
        final backend = FakeProductBackend();
        final api = ProductApiService(
          client: backend.client,
          baseUrl: () => testBaseUrl,
        );
        await expectLater(
          api.fetchProduct(99),
          throwsA(
            isA<ApiException>()
                .having((e) => e.isNotFound, 'isNotFound', isTrue)
                .having(
                  (e) => e.message,
                  'message',
                  'Product with id 99 was not found.',
                ),
          ),
        );

        final htmlApi = ProductApiService(
          client: MockClient(
            (_) async => http.Response('<html>Not Found</html>', 404),
          ),
          baseUrl: () => testBaseUrl,
        );
        await expectLater(
          htmlApi.fetchProducts(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('Unexpected response'),
            ),
          ),
        );

        final offlineApi = ProductApiService(
          client: MockClient(
            (_) async => throw http.ClientException('Connection refused'),
          ),
          baseUrl: () => testBaseUrl,
        );
        await expectLater(
          offlineApi.fetchProducts(),
          throwsA(
            isA<ApiException>()
                .having((e) => e.isConnectionError, 'isConnectionError', isTrue)
                .having(
                  (e) => e.message,
                  'message',
                  allOf(contains('internet'), contains('Server Settings')),
                ),
          ),
        );
      },
    );
  });

  group('ProductStore', () {
    test('keeps the list in sync after create, update and delete', () async {
      final backend = FakeProductBackend([
        productJson(id: 1, name: 'Lenovo Yoga 920', price: 1099.99, stock: 40),
        productJson(
          id: 2,
          name: 'Apple Airpods',
          category: 'Accessories',
          brand: 'Apple',
          price: 129.99,
          stock: 3,
          dummyId: 100,
        ),
      ]);
      final store = ProductStore(
        ProductApiService(client: backend.client, baseUrl: () => testBaseUrl),
      );
      var notifications = 0;
      store.addListener(() => notifications++);

      await store.load();
      expect(store.products.map((p) => p.name), [
        'Apple Airpods',
        'Lenovo Yoga 920',
      ]);
      expect(store.byDummyId(100)?.name, 'Apple Airpods');
      expect(store.byName('apple AIRPODS')?.id, 2);

      final ssd = await store.create(_ssd);
      expect(store.products.map((p) => p.name), [
        'Apple Airpods',
        'Lenovo Yoga 920',
        'Samsung 980 PRO 1TB NVMe SSD',
      ]);
      expect(store.recentlyAdded().first.name, _ssd.name);

      await store.update(ssd.copyWith(imageUrl: 'https://img/ssd.webp'));
      expect(store.byId(ssd.id!)!.imageUrl, 'https://img/ssd.webp');

      // Stats: 40 + 3 + 18 units.
      expect(store.totalUnits, 61);
      expect(
        store.inventoryValue,
        closeTo(1099.99 * 40 + 129.99 * 3 + 89.99 * 18, 0.001),
      );
      expect(store.lowStock.single.name, 'Apple Airpods');
      expect(store.outOfStockCount, 0);
      expect(store.countByCategory, {
        'Laptop': 1,
        'Parts': 1,
        'Accessories': 1,
      });

      await store.delete(1);
      expect(store.byId(1), isNull);
      expect(store.countByCategory['Laptop'], 0);
      expect(notifications, greaterThanOrEqualTo(5));
    });

    test('drops a row that was deleted on the server', () async {
      final backend = FakeProductBackend([
        productJson(id: 1, name: 'Dell XPS 13 9300', stock: 0),
      ]);
      final store = ProductStore(
        ProductApiService(client: backend.client, baseUrl: () => testBaseUrl),
      );
      await store.load();
      expect(store.outOfStockCount, 1);
      expect(store.stockAlerts.single.name, 'Dell XPS 13 9300');

      backend.rows.clear(); // deleted elsewhere, e.g. in phpMyAdmin
      final stale = store.byId(1)!;
      await expectLater(
        store.update(stale),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, '404', true)),
      );
      expect(store.byId(1), isNull);
      expect(await store.delete(1), 'This product had already been deleted.');
    });

    test('records the error when the server is unreachable', () async {
      final store = ProductStore(
        ProductApiService(
          client: MockClient(
            (_) async => throw http.ClientException('refused'),
          ),
          baseUrl: () => testBaseUrl,
        ),
      );
      await store.load();
      expect(store.hasLoaded, isFalse);
      expect(store.error, isNotNull);
      expect(store.isLoading, isFalse);
    });

    test('create() loads the whole list when it never loaded', () async {
      final backend = FakeProductBackend([
        productJson(id: 1, name: 'Huawei Matebook X Pro'),
      ]);
      final store = ProductStore(
        ProductApiService(client: backend.client, baseUrl: () => testBaseUrl),
      );
      await store.create(_ssd);
      expect(store.hasLoaded, isTrue);
      expect(store.products, hasLength(2));
    });
  });

  group('DummyJsonService', () {
    test('parses products in a category and caches them', () async {
      final log = <http.Request>[];
      final dummyJson = DummyJsonService(client: fakeDummyJsonClient(log: log));

      final laptops = await dummyJson.productsInCategory('laptops');
      expect(laptops.map((p) => p.id), [78, 79]);
      final macbook = laptops.first;
      expect(macbook.title, 'Apple MacBook Pro 14 Inch Space Grey');
      expect(macbook.price, 1999.99);
      expect(macbook.brand, 'Apple');
      expect(macbook.images, hasLength(2));
      expect(macbook.coverImage, endsWith('/78/thumbnail.webp'));
      expect(macbook.allImages, hasLength(3));
      expect(macbook.shopCategory, 'Laptop');
      expect(
        log.single.url.toString(),
        'https://dummyjson.com/products/category/laptops?limit=0',
      );

      await dummyJson.productsInCategory('laptops');
      expect(log, hasLength(1), reason: 'second call is served from cache');

      final accessories = await dummyJson.productsInCategory(
        'mobile-accessories',
      );
      final beats = accessories.firstWhere((p) => p.id == 107);
      expect(beats.brand, isEmpty, reason: 'DummyJSON left out "brand"');
      expect(beats.shopCategory, 'Accessories');
    });

    test('search keeps only tech categories', () async {
      final dummyJson = DummyJsonService(client: fakeDummyJsonClient());
      // "fake" matches every product description, including the mascara.
      final results = await dummyJson.search('fake');
      expect(results, hasLength(6));
      expect(results.any((p) => p.category == 'beauty'), isFalse);
      expect((await dummyJson.search('airpods')).single.id, 100);
    });

    test('fetches one product and surfaces 404 messages', () async {
      final dummyJson = DummyJsonService(client: fakeDummyJsonClient());
      final airpods = await dummyJson.product(100);
      expect(airpods.title, 'Apple Airpods');
      expect(airpods.discountedPrice, closeTo(116.34, 0.001));
      expect(airpods.warrantyInformation, '1 year warranty');

      await expectLater(
        dummyJson.product(99999),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNotFound, 'isNotFound', isTrue)
              .having(
                (e) => e.message,
                'message',
                "Product with id '99999' not found",
              ),
        ),
      );
    });

    test('picks the deal of the day from laptops and accessories', () async {
      final dummyJson = DummyJsonService(
        client: fakeDummyJsonClient(),
        random: Random(7),
      );
      for (var i = 0; i < 10; i++) {
        final deal = await dummyJson.randomDeal();
        expect(DummyJsonService.dealCategories, contains(deal.category));
      }
      final first = await dummyJson.randomDeal();
      final next = await dummyJson.randomDeal(excludeId: first.id);
      expect(next.id, isNot(first.id));
    });

    test('maps DummyJSON categories to shop categories and labels', () {
      expect(DummyJsonService.categoryToShop('laptops'), 'Laptop');
      expect(
        DummyJsonService.categoryToShop('mobile-accessories'),
        'Accessories',
      );
      expect(DummyJsonService.categoryToShop('tablets'), 'Accessories');
      expect(DummyJsonService.categoryToShop('smartphones'), 'Accessories');
      expect(
        DummyJsonService.categoryLabel('mobile-accessories'),
        'Accessories',
      );
      expect(
        DummyJsonService.categoryLabel('home-decoration'),
        'Home Decoration',
      );
      expect(
        DummyProduct.fromJson(const {'id': 5, 'title': 'X'}).images,
        isEmpty,
      );
    });
  });

  group('formatPrice', () {
    test('adds a dollar sign, cents and thousands separators', () {
      expect(formatPrice(0.5), r'$0.50');
      expect(formatPrice(49.99), r'$49.99');
      expect(formatPrice(1999.99), r'$1,999.99');
      expect(formatPrice(1000000), r'$1,000,000.00');
      expect(formatPrice(0.01), r'$0.01');
      expect(formatPrice(1234.5, cents: false), r'$1,235');
      expect(formatNumber(100000), '100,000');
      expect(formatNumber(999), '999');
      expect(pluralize(1, 'product'), '1 product');
      expect(pluralize(3, 'product'), '3 products');
      expect(formatDate(DateTime(2026, 9, 26)), 'Sep 26, 2026');
    });
  });
}
