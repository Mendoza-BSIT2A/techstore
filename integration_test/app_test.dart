import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:techstore/config/api_config.dart';
import 'package:techstore/main.dart';
import 'package:techstore/services/app_services.dart';
import 'package:techstore/utils/format.dart';

/// End-to-end CRUD + DummyJSON check against the LIVE backend.
///
/// 1. Uses the default (online Supabase) API; for the local PHP API start
///    `php -S 0.0.0.0:8000 -t backend` and pass API_BASE_URL as below.
/// 2. Run on an emulator:
///    flutter drive --driver=test_driver/integration_test.dart \
///      --target=integration_test/app_test.dart \
///      --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
///
/// Add --dart-define=SCREENSHOTS=true to save screenshots to docs/screenshots/.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps frames for [ms] milliseconds without waiting for spinners to stop.
  Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String reason = 'condition',
    int timeoutSeconds = 20,
  }) async {
    final end = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (!condition()) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $reason');
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) =>
      pumpUntil(tester, () => finder.evaluate().isNotEmpty, reason: '$finder');

  // Screenshots need `flutter drive` (see above) plus --dart-define=SCREENSHOTS=true.
  const takeScreenshots = bool.fromEnvironment('SCREENSHOTS');
  var surfaceConverted = false;
  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!takeScreenshots) return;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        !surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
    }
    await settle(tester, 300);
    await binding.takeScreenshot(name);
  }

  Future<void> choose(WidgetTester tester, String key, String value) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await settle(tester, 600);
    await tester.tap(find.text(value).last);
    await settle(tester, 600);
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.enterText(find.byKey(Key(key)), text);
    await tester.pump();
  }

  testWidgets('full CRUD flow against the live API + DummyJSON', (
    tester,
  ) async {
    // In-memory only, so the device's saved Server Settings stay untouched.
    ApiConfig.baseUrl.value = ApiConfig.defaultBaseUrl;
    final name =
        'Test Laptop ${DateTime.now().millisecondsSinceEpoch % 100000}';
    final store = AppServices.productStore;

    // ---------------------------------------------------------------- HOME
    await tester.pumpWidget(const TechStoreApp());
    await pumpUntil(
      tester,
      () => store.hasLoaded || store.error != null,
      reason: 'products to load',
    );
    expect(
      store.error,
      isNull,
      reason: 'API at ${ApiConfig.baseUrl.value} must be running',
    );
    final initialCount = store.products.length;
    await settle(tester, 3000); // let the DummyJSON deal arrive
    await screenshot(tester, '01_home');

    // ---------------------------------------------------------------- READ
    await tester.tap(find.text('Inventory').last);
    await settle(tester, 2500);
    expect(find.text(pluralize(initialCount, 'product')), findsOneWidget);
    await screenshot(tester, '02_list_grid');

    await tester.tap(find.byTooltip('Show as list'));
    await settle(tester, 1500);
    await screenshot(tester, '03_list_rows');
    await tester.tap(find.byTooltip('Show as grid'));
    await settle(tester);

    // -------------------------------------------------------------- CREATE
    await tester.tap(find.byKey(const Key('add_product')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('submit_product')));
    await settle(tester);
    expect(find.text('Please enter the product name.'), findsOneWidget);
    expect(find.text('Please choose a category.'), findsOneWidget);
    await screenshot(tester, '04_create_validation');

    await type(tester, 'field_name', name);
    await choose(tester, 'field_category', 'Laptop');
    await type(tester, 'field_brand', 'Testbrand');
    await type(tester, 'field_price', '1234.5');
    await type(tester, 'field_stock', '7');
    await type(
      tester,
      'field_description',
      'Created by the automated end-to-end test.',
    );
    await type(
      tester,
      'field_image_url',
      'https://cdn.dummyjson.com/product-images/laptops/lenovo-yoga-920/thumbnail.webp',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester, 2000);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, 2000),
    );
    await settle(tester, 800);
    await screenshot(tester, '05_create_filled');

    await tester.tap(find.byKey(const Key('submit_product')));
    await pumpUntil(
      tester,
      () => store.byName(name) != null,
      reason: 'POST to finish',
    );
    await settle(tester, 2500);
    expect(store.products.length, initialCount + 1);
    expect(store.byName(name)!.price, 1234.5);
    await screenshot(tester, '06_after_create');

    // -------------------------------------------------------------- DETAIL
    await tester.enterText(find.byType(TextField).first, name);
    await settle(tester, 1500);
    await tester.tap(find.text(name).last);
    await settle(tester, 3500);
    expect(find.text('Testbrand'), findsOneWidget);
    expect(find.text(r'$1,234.50'), findsOneWidget);
    await screenshot(tester, '07_detail');

    // -------------------------------------------------------------- UPDATE
    await tester.tap(find.byKey(const Key('edit_product')));
    await settle(tester);
    expect(find.text('Edit Product'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, name),
      findsOneWidget,
      reason: 'pre-populated',
    );
    await type(tester, 'field_brand', 'Testbrand (updated)');
    await type(tester, 'field_stock', '3');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester, 800);
    await screenshot(tester, '08_edit_prefilled');

    await tester.tap(find.byKey(const Key('submit_product')));
    await pumpUntil(
      tester,
      () => store.byName(name)?.brand == 'Testbrand (updated)',
      reason: 'PUT to finish',
    );
    await settle(tester, 2000);
    expect(find.text('Testbrand (updated)'), findsOneWidget);
    expect(find.text('Low stock · 3 left'), findsOneWidget);
    await screenshot(tester, '09_detail_updated');

    // -------------------------------------------------------------- DELETE
    await tester.tap(find.byKey(const Key('delete_product')));
    await settle(tester);
    expect(find.text('Delete $name?'), findsOneWidget);
    await screenshot(tester, '10_delete_confirm');

    await tester.tap(find.byKey(const Key('confirm_delete')));
    await pumpUntil(
      tester,
      () => store.byName(name) == null,
      reason: 'DELETE to finish',
    );
    await settle(tester, 1500);
    expect(store.products.length, initialCount);
    await tester.enterText(find.byType(TextField).first, '');
    await settle(tester, 1500);
    await screenshot(tester, '11_after_delete');

    // ----------------------------------------------------------- DUMMYJSON
    await tester.tap(find.text('Explore').last);
    await pumpUntilFound(
      tester,
      find.textContaining('live from dummyjson.com'),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Laptops'));
    await settle(tester, 4000);
    await screenshot(tester, '12_explore');

    await tester.tap(find.textContaining('MacBook Pro').first);
    await pumpUntilFound(
      tester,
      find.textContaining('GET https://dummyjson.com/products/'),
    );
    await settle(tester, 4000);
    await screenshot(tester, '13_explore_product');
  });
}
