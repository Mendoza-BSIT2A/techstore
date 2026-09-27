import 'dummyjson_service.dart';
import 'product_api_service.dart';
import 'product_store.dart';

/// App-wide service instances. Tests can replace these before pumping widgets.
class AppServices {
  AppServices._();

  static ProductStore productStore = ProductStore(ProductApiService());
  static DummyJsonService dummyJson = DummyJsonService();
}
