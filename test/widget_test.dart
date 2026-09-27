import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techstore/main.dart';
import 'package:techstore/models/product.dart';
import 'package:techstore/screens/product_detail_screen.dart';
import 'package:techstore/screens/product_form_screen.dart';
import 'package:techstore/screens/product_list_screen.dart';
import 'package:techstore/services/app_services.dart';

import 'support/fakes.dart';

/// Phone-sized surface so the bottom navigation layout is used.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
}

/// Hosts [screen] behind a button so tests can check what it pops with.
Future<List<Object?>> pumpPushed(WidgetTester tester, Widget screen) async {
  final results = <Object?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => results.add(
                await Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => screen)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

Future<void> selectDropdown(
  WidgetTester tester,
  String key,
  String value,
) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> tapSubmit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('submit_product')));
  await tester.pumpAndSettle();
}

/// Current text of the form field with [key].
String fieldText(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

void main() {
  const macbook = 'Apple MacBook Pro 14 Inch Space Grey';
  const ram = 'Kingston FURY Beast 16GB DDR4-3200 RAM';

  final seed = [
    productJson(
      id: 1,
      name: macbook,
      brand: 'Apple',
      price: 1999.99,
      stock: 24,
      dummyId: 78,
    ),
    productJson(
      id: 2,
      name: ram,
      category: 'Parts',
      brand: 'Kingston',
      price: 49.99,
      stock: 4,
      description: '16GB DDR4 desktop memory module.',
      createdAt: '2026-09-20 10:00:00',
    ),
  ];

  testWidgets('home screen shows the DummyJSON deal and inventory stats', (
    tester,
  ) async {
    usePhoneScreen(tester);
    installFakeServices(seed);

    await tester.pumpWidget(const TechStoreApp());
    await tester.pumpAndSettle();

    expect(find.text('Deal of the Day'), findsOneWidget);
    const dealTitles = [
      macbook,
      'Asus Zenbook Pro Dual Screen Laptop',
      'Apple Airpods',
      'Beats Flex Wireless Earphones',
    ];
    expect(
      dealTitles.any((title) => find.text(title).evaluate().isNotEmpty),
      isTrue,
      reason: 'a laptop or accessory from DummyJSON is shown',
    );
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Units in stock'), findsOneWidget);
    expect(find.text('28'), findsOneWidget); // 24 + 4 units
    expect(find.text('Inventory value'), findsOneWidget);
    expect(find.text(r'$48,200'), findsOneWidget); // 1999.99×24 + 49.99×4

    // The RAM (4 left) is listed under Stock alerts.
    await tester.ensureVisible(find.text('Stock alerts'));
    expect(find.text(r'Parts · $49.99 · 4 left'), findsOneWidget);

    await tester.tap(find.text('Inventory').last);
    await tester.pumpAndSettle();
    expect(find.text('2 products'), findsOneWidget);
    expect(find.byKey(const Key('add_product')), findsOneWidget);
  });

  testWidgets('list screen searches, filters and sorts products', (
    tester,
  ) async {
    usePhoneScreen(tester);
    installFakeServices(seed);
    await AppServices.productStore.load();

    await tester.pumpWidget(const MaterialApp(home: ProductListScreen()));
    await tester.pumpAndSettle();
    expect(find.text(macbook), findsOneWidget);
    expect(find.text(ram), findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);

    // Matches the description of the RAM only.
    await tester.enterText(find.byType(TextField).first, 'desktop memory');
    await tester.pumpAndSettle();
    expect(find.text(macbook), findsNothing);
    expect(find.text(ram), findsOneWidget);
    expect(find.text('Showing 1 of 2 products'), findsOneWidget);

    // Matches the brand.
    await tester.enterText(find.byType(TextField).first, 'apple');
    await tester.pumpAndSettle();
    expect(find.text(macbook), findsOneWidget);
    expect(find.text(ram), findsNothing);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.widgetWithText(FilterChip, 'Parts'));
    await tester.pumpAndSettle();
    expect(find.text(macbook), findsNothing);
    expect(find.text(ram), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Parts'));
    await tester.pumpAndSettle();
    expect(find.text(macbook), findsOneWidget);

    // Name order puts the MacBook first; price low-high puts the RAM first.
    double left(String text) => tester.getTopLeft(find.text(text)).dx;
    expect(left(macbook), lessThan(left(ram)));
    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Price: low to high'));
    await tester.pumpAndSettle();
    expect(left(ram), lessThan(left(macbook)));
  });

  testWidgets(
    'create form validates input, then POSTs and returns the new product',
    (tester) async {
      usePhoneScreen(tester);
      final backend = installFakeServices(seed);
      await AppServices.productStore.load();

      final results = await pumpPushed(tester, const ProductFormScreen());

      await tapSubmit(tester);
      expect(find.text('Please enter the product name.'), findsOneWidget);
      expect(find.text('Please choose a category.'), findsOneWidget);
      expect(find.text('Please enter a price.'), findsOneWidget);
      expect(find.text('Please enter the stock quantity.'), findsOneWidget);
      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);

      // Duplicate name (any case), zero price and too much stock are caught
      // on the device.
      await tester.enterText(
        find.byKey(const Key('field_name')),
        macbook.toLowerCase(),
      );
      await tester.enterText(find.byKey(const Key('field_price')), '0');
      await tester.enterText(find.byKey(const Key('field_stock')), '100001');
      await tapSubmit(tester);
      expect(
        find.text('You already have a product with this name.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Price must be a number from 0.01 to 1,000,000 with at most 2 decimals.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Stock must be a whole number from 0 to 100,000.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('field_name')),
        'Samsung 980 PRO 1TB NVMe SSD',
      );
      await selectDropdown(tester, 'field_category', 'Parts');
      await tester.enterText(find.byKey(const Key('field_brand')), 'Samsung');
      await tester.enterText(find.byKey(const Key('field_price')), '89.99');
      await tester.enterText(find.byKey(const Key('field_stock')), '18');
      await tester.enterText(
        find.byKey(const Key('field_image_url')),
        'ftp://example.com/ssd.webp',
      );
      await tapSubmit(tester);
      expect(find.textContaining('Enter a full link'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('field_image_url')), '');
      await tapSubmit(tester);

      final post = backend.requests.singleWhere((r) => r.method == 'POST');
      expect(post.body, contains('"name":"Samsung 980 PRO 1TB NVMe SSD"'));
      expect(post.body, contains('"category":"Parts"'));
      expect(post.body, contains('"price":89.99'));
      expect(post.body, contains('"stock":18'));
      expect(results.single, isA<Product>().having((p) => p.id, 'id', 3));
      expect(
        AppServices.productStore.byName('Samsung 980 PRO 1TB NVMe SSD'),
        isNotNull,
      );
    },
  );

  testWidgets('price field accepts at most two decimals', (tester) async {
    usePhoneScreen(tester);
    installFakeServices(seed);
    await pumpPushed(tester, const ProductFormScreen());

    await tester.enterText(find.byKey(const Key('field_price')), '12.34');
    expect(fieldText(tester, 'field_price'), '12.34');

    // A third decimal, a second dot and letters are rejected as you type.
    await tester.enterText(find.byKey(const Key('field_price')), '12.345');
    expect(fieldText(tester, 'field_price'), '12.34');
    await tester.enterText(find.byKey(const Key('field_price')), '12.3.4');
    expect(fieldText(tester, 'field_price'), '12.34');
    await tester.enterText(find.byKey(const Key('field_price')), '12a');
    expect(fieldText(tester, 'field_price'), '12.34');

    // A decimal comma becomes a dot.
    await tester.enterText(find.byKey(const Key('field_price')), '7,5');
    expect(fieldText(tester, 'field_price'), '7.5');

    // Stock takes whole numbers only.
    await tester.enterText(find.byKey(const Key('field_stock')), '3.5');
    expect(fieldText(tester, 'field_stock'), '35');
  });

  testWidgets('picking a DummyJSON product fills only the empty fields', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final backend = installFakeServices(seed);
    await AppServices.productStore.load();
    await pumpPushed(tester, const ProductFormScreen());

    await tester.enterText(find.byKey(const Key('field_name')), 'Zenbook Duo');
    await tester.ensureVisible(find.byKey(const Key('field_dummyjson')));
    await tester.tap(find.byKey(const Key('field_dummyjson')));
    await tester.pumpAndSettle();
    expect(find.text('Link a DummyJSON product'), findsOneWidget);

    await tester.tap(find.text('Asus Zenbook Pro Dual Screen Laptop'));
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'field_name'), 'Zenbook Duo'); // kept
    expect(fieldText(tester, 'field_brand'), 'Asus');
    expect(fieldText(tester, 'field_price'), '1799.99');
    expect(fieldText(tester, 'field_stock'), '20');
    expect(
      fieldText(tester, 'field_image_url'),
      'https://cdn.dummyjson.com/product-images/79/thumbnail.webp',
    );
    expect(find.text('Laptop'), findsOneWidget); // category dropdown

    await tapSubmit(tester);
    final post = backend.requests.singleWhere((r) => r.method == 'POST');
    expect(post.body, contains('"dummyjson_id":79'));
    expect(post.body, contains('"category":"Laptop"'));
    expect(post.body, contains('"name":"Zenbook Duo"'));
  });

  testWidgets('server-side 422 errors appear under the matching field', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final backend = installFakeServices(seed);
    await AppServices.productStore.load();
    backend.nextValidationErrors = {
      'name': 'A product with this name already exists.',
    };

    final product = AppServices.productStore.byId(1)!;
    final results = await pumpPushed(
      tester,
      ProductFormScreen(product: product),
    );

    expect(find.text('Edit Product'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, macbook), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '1999.99'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '24'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('field_name')),
      'MacBook Pro 14 (2021)',
    );
    await tapSubmit(tester);
    expect(
      find.text('A product with this name already exists.'),
      findsOneWidget,
    );
    expect(results, isEmpty);

    // Retrying succeeds and sends a PUT for the same id.
    await tapSubmit(tester);
    final put = backend.requests.lastWhere((r) => r.method == 'PUT');
    expect(put.url.queryParameters['id'], '1');
    expect(put.body, contains('"dummyjson_id":78'));
    expect(AppServices.productStore.byId(1)!.name, 'MacBook Pro 14 (2021)');
    expect(results.single, isA<Product>());
  });

  testWidgets('leaving a form with unsaved changes asks for confirmation', (
    tester,
  ) async {
    usePhoneScreen(tester);
    installFakeServices(seed);
    await pumpPushed(tester, const ProductFormScreen());

    await tester.enterText(find.byKey(const Key('field_name')), 'Half-written');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('detail screen shows live DummyJSON data for a linked product', (
    tester,
  ) async {
    usePhoneScreen(tester);
    installFakeServices(seed);
    await AppServices.productStore.load();

    await pumpPushed(tester, const ProductDetailScreen(productId: 1));
    expect(find.text(r'$1,999.99'), findsOneWidget);
    expect(find.text('24 in stock'), findsOneWidget);

    await tester.ensureVisible(find.text('Rating: 4.5 / 5'));
    expect(find.text('Warranty: 1 year warranty'), findsOneWidget);
    expect(find.text('Shipping: Ships in 1 week'), findsOneWidget);
  });

  testWidgets('detail screen confirms before deleting', (tester) async {
    usePhoneScreen(tester);
    final backend = installFakeServices(seed);
    await AppServices.productStore.load();

    await pumpPushed(tester, const ProductDetailScreen(productId: 2));
    expect(find.text(ram), findsWidgets);
    expect(find.text('Kingston'), findsOneWidget);
    expect(find.text(r'$49.99'), findsOneWidget);
    expect(find.text(r'$199.96'), findsOneWidget); // stock value 49.99 × 4
    expect(
      backend.requests.any(
        (r) => r.method == 'GET' && r.url.queryParameters['id'] == '2',
      ),
      isTrue,
    );
    await tester.ensureVisible(find.text('Not linked to DummyJSON'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete_product')));
    await tester.pumpAndSettle();
    expect(find.text('Delete $ram?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.requests.where((r) => r.method == 'DELETE'), isEmpty);

    await tester.tap(find.byKey(const Key('delete_product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_delete')));
    await tester.pumpAndSettle();

    expect(
      backend.requests
          .where((r) => r.method == 'DELETE')
          .single
          .url
          .queryParameters['id'],
      '2',
    );
    expect(AppServices.productStore.byId(2), isNull);
    expect(find.text('open'), findsOneWidget); // popped back
    expect(find.text('Product "$ram" deleted.'), findsOneWidget);
  });
}
