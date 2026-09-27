import 'package:flutter/material.dart';

import '../models/dummy_product.dart';
import '../models/product.dart';
import '../services/api_exception.dart';
import '../services/app_services.dart';
import '../utils/format.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/product_card.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';
import 'product_form_screen.dart';

/// Shows one product (GET products.php?id=) with edit and delete actions,
/// plus live details of the linked product from the DummyJSON API.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId, this.heroTag});

  final int productId;
  final Object? heroTag;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _store = AppServices.productStore;

  bool _loading = true;
  bool _deleting = false;
  ApiException? _error;
  Product? _lastShown;

  int? _dummyId;
  Future<DummyProduct>? _dummy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _store.refreshOne(widget.productId);
    } on ApiException catch (e) {
      _error = e;
      // Still showing a cached copy: say that the refresh failed.
      if (mounted && !e.isNotFound && _store.byId(widget.productId) != null) {
        showAppSnackBar(context, e.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadDummy(int id) {
    _dummyId = id;
    _dummy = AppServices.dummyJson.product(id);
  }

  Future<void> _edit(Product product) async {
    final saved = await Navigator.of(context).push<Product>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    );
    if (saved != null && mounted) {
      showAppSnackBar(context, 'Saved changes to "${saved.name}".');
    }
  }

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
          title: Text('Delete ${product.name}?'),
          content: Text(
            'This permanently removes "${product.name}" from your inventory. '
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_delete'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final message = await _store.delete(product.id!);
      if (!mounted) return;
      showAppSnackBar(context, message);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showAppSnackBar(context, e.message, isError: true);
    }
  }

  Future<void> _setCoverPhoto(Product product, String url) async {
    Navigator.of(context).pop(); // close the photo viewer
    try {
      await _store.update(product.copyWith(imageUrl: url));
      if (mounted) showAppSnackBar(context, 'Cover photo updated.');
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final product =
            _store.byId(widget.productId) ?? (_deleting ? _lastShown : null);

        if (product == null) {
          return Scaffold(
            appBar: AppBar(),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : ErrorView(
                    title: _error?.isNotFound ?? true
                        ? 'Product not found'
                        : 'Could not load this product',
                    message:
                        _error?.message ??
                        'This product may have been deleted.',
                    onRetry: _error?.isNotFound ?? true ? null : _load,
                    showSettingsButton: _error?.isConnectionError ?? false,
                  ),
          );
        }

        _lastShown = product;
        final dummyId = product.dummyJsonId;
        if (dummyId != _dummyId) {
          if (dummyId == null) {
            _dummyId = null;
            _dummy = null;
          } else {
            _loadDummy(dummyId);
          }
        }

        return Scaffold(
          // Block taps while deleting so nothing else opens before the page closes.
          body: AbsorbPointer(
            absorbing: _deleting,
            child: RefreshIndicator(
              onRefresh: _load,
              edgeOffset: 120,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _header(context, product),
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _details(context, product),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, Product product) {
    final scheme = Theme.of(context).colorScheme;
    // A dark bar with light content in both themes, so the title and icons
    // stay readable over the darkened photo.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = isDark ? scheme.primaryContainer : scheme.primary;
    final onBarColor = isDark ? scheme.onPrimaryContainer : scheme.onPrimary;
    // Shop photos are shown whole on white, like in a store catalogue.
    final image = ProductImage(
      product.imageUrl,
      fit: BoxFit.contain,
      backgroundColor: Colors.white,
      iconSize: 72,
      semanticLabel: product.name,
    );

    // Dark translucent circles keep the toolbar buttons readable on any
    // photo, including white product shots.
    final toolbarButton = IconButton.styleFrom(
      backgroundColor: Colors.black38,
      foregroundColor: Colors.white,
    );

    return SliverAppBar(
      pinned: true,
      expandedHeight: 300,
      leading: BackButton(style: toolbarButton),
      backgroundColor: barColor,
      foregroundColor: onBarColor,
      surfaceTintColor: Colors.transparent,
      bottom: _deleting || (_loading && _error == null)
          ? const PreferredSize(
              preferredSize: Size.fromHeight(3),
              child: LinearProgressIndicator(minHeight: 3),
            )
          : null,
      actions: [
        IconButton(
          key: const Key('edit_product'),
          tooltip: 'Edit',
          style: toolbarButton,
          onPressed: _deleting ? null : () => _edit(product),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          key: const Key('delete_product'),
          tooltip: 'Delete',
          style: toolbarButton,
          onPressed: _deleting ? null : () => _confirmDelete(product),
          icon: const Icon(Icons.delete_outline),
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: Builder(
        builder: (context) {
          // When collapsed, stop the title before the Edit and Delete icons.
          final bar = context
              .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()!;
          final collapsed =
              ((bar.maxExtent - bar.currentExtent) /
                      (bar.maxExtent - bar.minExtent))
                  .clamp(0.0, 1.0);
          return FlexibleSpaceBar(
            titlePadding: EdgeInsetsDirectional.only(
              start: 16 + 56 * collapsed,
              end: 16 + 96 * collapsed,
              bottom: 16,
            ),
            title: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: onBarColor, fontWeight: FontWeight.w600),
            ),
            background: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: product.hasImage
                      ? () => showPhotoViewer(
                          context,
                          product.imageUrl!,
                          caption: product.name,
                        )
                      : null,
                  child: widget.heroTag == null
                      ? image
                      : Hero(tag: widget.heroTag!, child: image),
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.25, 0.45, 0.6, 1],
                        colors: [
                          Color(0x99000000),
                          Color(0x66000000),
                          Color(0x00000000),
                          Color(0x00000000),
                          Color(0xAA000000),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _details(BuildContext context, Product product) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                formatPrice(product.price),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              StockBadge(
                product: product,
                showWhenInStock: true,
                detailed: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Fact(
                  icon: Icons.category_outlined,
                  label: 'Category',
                  value: product.category,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Fact(
                  icon: Icons.sell_outlined,
                  label: 'Brand',
                  value: product.brand.isEmpty ? 'Unbranded' : product.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Fact(
                  icon: Icons.inventory_2_outlined,
                  label: 'Stock',
                  value: pluralize(product.stock, 'unit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Fact(
                  icon: Icons.payments_outlined,
                  label: 'Stock value',
                  value: formatPrice(product.inventoryValue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('About this product', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            product.description.isEmpty
                ? 'No description yet.'
                : product.description,
            style: product.description.isEmpty
                ? muted
                : theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          _dummyJsonSection(context, product),
          const SizedBox(height: 28),
          Text(
            'Record #${product.id}'
            '${product.createdAt == null ? '' : ' · Added ${formatDate(product.createdAt!)}'}'
            '${product.updatedAt == null ? '' : ' · Updated ${formatDate(product.updatedAt!)}'}',
            style: muted,
          ),
        ],
      ),
    );
  }

  Widget _dummyJsonSection(BuildContext context, Product product) {
    final theme = Theme.of(context);
    final dummyId = product.dummyJsonId;
    final dummy = _dummy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('From DummyJSON', style: theme.textTheme.titleMedium),
                  Text(
                    dummyId == null
                        ? 'Live product data from dummyjson.com'
                        : 'Live from dummyjson.com · product #$dummyId',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (dummyId != null)
              IconButton(
                tooltip: 'Reload DummyJSON data',
                onPressed: () => setState(() => _loadDummy(dummyId)),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (dummyId == null || dummy == null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Not linked to DummyJSON'),
              subtitle: const Text(
                'Edit this product and pick a DummyJSON product to see its '
                'rating, warranty, shipping and photos.',
              ),
              onTap: () => _edit(product),
            ),
          )
        else
          FutureBuilder<DummyProduct>(
            future: dummy,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 132,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.cloud_off,
                      color: theme.colorScheme.error,
                    ),
                    title: const Text('Could not load DummyJSON data'),
                    subtitle: Text(
                      '${snapshot.error}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Try again',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => setState(() => _loadDummy(dummyId)),
                    ),
                  ),
                );
              }
              return _dummyJsonDetails(context, product, snapshot.data!);
            },
          ),
      ],
    );
  }

  Widget _dummyJsonDetails(
    BuildContext context,
    Product product,
    DummyProduct dummy,
  ) {
    final theme = Theme.of(context);
    final urls = dummy.allImages;
    String orDash(String value) => value.isEmpty ? '—' : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dummy.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.star_rounded,
                  iconColor: Colors.amber.shade700,
                  label: 'Rating',
                  value: '${dummy.rating.toStringAsFixed(1)} / 5',
                ),
                _InfoRow(
                  icon: Icons.local_offer_outlined,
                  label: 'Discount',
                  value: dummy.hasDiscount
                      ? '${dummy.discountPercentage.toStringAsFixed(0)}% off '
                            '(${formatPrice(dummy.discountedPrice)} instead of '
                            '${formatPrice(dummy.price)})'
                      : 'No discount (${formatPrice(dummy.price)})',
                ),
                _InfoRow(
                  icon: Icons.verified_user_outlined,
                  label: 'Warranty',
                  value: orDash(dummy.warrantyInformation),
                ),
                _InfoRow(
                  icon: Icons.local_shipping_outlined,
                  label: 'Shipping',
                  value: orDash(dummy.shippingInformation),
                ),
                _InfoRow(
                  icon: Icons.storefront_outlined,
                  label: 'Availability',
                  value: dummy.availabilityStatus.isEmpty
                      ? pluralize(dummy.stock, 'unit')
                      : '${dummy.availabilityStatus} · ${pluralize(dummy.stock, 'unit')}',
                ),
              ],
            ),
          ),
        ),
        if (urls.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final url = urls[index];
                return SizedBox(
                  width: 132,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => showPhotoViewer(
                      context,
                      url,
                      caption:
                          'Photo ${index + 1} of ${urls.length} · dummyjson.com',
                      action: url == product.imageUrl
                          ? null
                          : FilledButton.icon(
                              onPressed: () => _setCoverPhoto(product, url),
                              icon: const Icon(Icons.wallpaper),
                              label: const Text('Use as cover photo'),
                            ),
                    ),
                    child: ProductImage(
                      url,
                      fit: BoxFit.contain,
                      backgroundColor: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled line of the DummyJSON card.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
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
          Icon(icon, size: 20, color: iconColor ?? theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: value),
                ],
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
