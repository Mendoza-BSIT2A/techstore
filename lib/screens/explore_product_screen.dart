import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/dummy_product.dart';
import '../models/product.dart';
import '../services/app_services.dart';
import '../services/dummyjson_service.dart';
import '../utils/format.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

/// One DummyJSON product (GET /products/{id}) with a shortcut to add it to
/// the inventory.
class ExploreProductScreen extends StatefulWidget {
  const ExploreProductScreen({
    super.key,
    required this.productId,
    this.initial,
  });

  final int productId;

  /// Already-loaded copy (e.g. from the Explore grid) shown while refreshing.
  final DummyProduct? initial;

  @override
  State<ExploreProductScreen> createState() => _ExploreProductScreenState();
}

class _ExploreProductScreenState extends State<ExploreProductScreen> {
  late Future<DummyProduct> _product = _fetch();
  final _pages = PageController();
  int _page = 0;
  bool _opening = false;

  Future<DummyProduct> _fetch() =>
      AppServices.dummyJson.product(widget.productId);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final future = _fetch();
    setState(() {
      _product = future;
    });
    try {
      await future;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  Future<void> _save(DummyProduct product, {String? imageUrl}) async {
    // Ignore repeat taps while the form is opening.
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final saved = await Navigator.of(context).push<Product>(
        MaterialPageRoute(
          builder: (_) =>
              ProductFormScreen(prefill: product, prefillImageUrl: imageUrl),
        ),
      );
      if (saved != null && mounted) {
        showAppSnackBar(context, 'Added "${saved.name}" to the inventory.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _openSaved(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: product.id!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = AppServices.productStore;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => FutureBuilder<DummyProduct>(
        future: _product,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          // Keep showing the copy from the grid while loading or if the
          // refresh fails.
          final product =
              snapshot.data ??
              (loading || snapshot.hasError ? widget.initial : null);
          final saved = product == null
              ? null
              : store.byDummyId(product.id) ?? store.byName(product.title);

          return Scaffold(
            appBar: AppBar(
              title: Text(product?.title ?? 'Product'),
              actions: [
                IconButton(
                  tooltip: 'Reload',
                  onPressed: loading ? null : _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
              bottom: loading && product != null
                  ? const PreferredSize(
                      preferredSize: Size.fromHeight(3),
                      child: LinearProgressIndicator(minHeight: 3),
                    )
                  : null,
            ),
            body: product == null
                ? loading
                      ? const Center(child: CircularProgressIndicator())
                      : ErrorView(
                          title: 'Could not load this product',
                          message: '${snapshot.error}',
                          onRetry: _reload,
                        )
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: _content(context, product, saved),
                          ),
                        ),
                      ],
                    ),
                  ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: saved != null
                    ? FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: () => _openSaved(saved),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('View in inventory'),
                      )
                    : FilledButton.icon(
                        key: const Key('add_to_inventory'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: _opening || product == null
                            ? null
                            : () => _save(product),
                        icon: const Icon(Icons.add),
                        label: const Text('Add to inventory'),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, DummyProduct product, Product? saved) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final images = product.allImages;
    final page = _page.clamp(0, images.isEmpty ? 0 : images.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 300,
          child: images.isEmpty
              ? const ProductImage(null, iconSize: 72)
              : PageView.builder(
                  controller: _pages,
                  itemCount: images.length,
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (context, index) {
                    final url = images[index];
                    return GestureDetector(
                      onTap: () => showPhotoViewer(
                        context,
                        url,
                        caption:
                            '${product.title} · photo ${index + 1} of ${images.length}',
                        action: saved != null
                            ? null
                            : FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _save(product, imageUrl: url);
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Add with this photo'),
                              ),
                      ),
                      child: ProductImage(
                        url,
                        fit: BoxFit.contain,
                        backgroundColor: Colors.white,
                        iconSize: 72,
                        semanticLabel: product.title,
                      ),
                    );
                  },
                ),
        ),
        if (images.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < images.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == page ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                [
                  if (product.brand.isNotEmpty) product.brand,
                  DummyJsonService.categoryLabel(product.category),
                ].join(' · '),
                style: muted,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    formatPrice(product.discountedPrice),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (product.hasDiscount) ...[
                    Text(
                      formatPrice(product.price),
                      style: muted?.copyWith(
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Chip(
                      label: Text(
                        '-${product.discountPercentage.toStringAsFixed(0)}%',
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.errorContainer,
                      labelStyle: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                      side: BorderSide.none,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    Icon(
                      product.rating >= i
                          ? Icons.star_rounded
                          : product.rating >= i - 0.5
                          ? Icons.star_half_rounded
                          : Icons.star_outline_rounded,
                      size: 20,
                      color: Colors.amber.shade700,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    '${product.rating.toStringAsFixed(1)} / 5',
                    style: muted,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Column(
                    children: [
                      _Spec(
                        icon: Icons.sell_outlined,
                        label: 'Brand',
                        value: product.brand.isEmpty ? '—' : product.brand,
                      ),
                      _Spec(
                        icon: Icons.inventory_2_outlined,
                        label: 'Stock',
                        value: product.availabilityStatus.isEmpty
                            ? pluralize(product.stock, 'unit')
                            : '${pluralize(product.stock, 'unit')} · ${product.availabilityStatus}',
                      ),
                      _Spec(
                        icon: Icons.verified_user_outlined,
                        label: 'Warranty',
                        value: product.warrantyInformation.isEmpty
                            ? '—'
                            : product.warrantyInformation,
                      ),
                      _Spec(
                        icon: Icons.local_shipping_outlined,
                        label: 'Shipping',
                        value: product.shippingInformation.isEmpty
                            ? '—'
                            : product.shippingInformation,
                      ),
                      if (product.sku.isNotEmpty)
                        _Spec(
                          icon: Icons.qr_code_2,
                          label: 'SKU',
                          value: product.sku,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Description', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                product.description.isEmpty
                    ? 'No description.'
                    : product.description,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.api),
                  title: const Text('Live product data'),
                  subtitle: Text(
                    'GET ${ApiConfig.dummyJsonBaseUrl}/products/${product.id}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Spec extends StatelessWidget {
  const _Spec({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(84),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
