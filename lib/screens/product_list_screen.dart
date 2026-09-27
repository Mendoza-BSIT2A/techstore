import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/app_services.dart';
import '../utils/format.dart';
import '../widgets/product_card.dart';
import '../widgets/state_views.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

enum _SortOrder { name, newest, priceLowHigh, priceHighLow }

/// Inventory: every record from the custom API in a responsive grid or list.
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => ProductListScreenState();
}

class ProductListScreenState extends State<ProductListScreen> {
  final _store = AppServices.productStore;
  final _search = TextEditingController();

  String _query = '';
  String? _category;
  _SortOrder _sort = _SortOrder.name;
  bool _gridView = true;
  bool _opening = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _hasFilters => _query.isNotEmpty || _category != null;

  List<Product> _visible(List<Product> all) {
    final query = _query.trim().toLowerCase();
    final result = all.where((product) {
      if (_category != null && product.category != _category) return false;
      if (query.isEmpty) return true;
      return product.name.toLowerCase().contains(query) ||
          product.brand.toLowerCase().contains(query) ||
          product.description.toLowerCase().contains(query);
    }).toList();

    switch (_sort) {
      case _SortOrder.name:
        break; // the store keeps products sorted by name
      case _SortOrder.newest:
        result.sort((a, b) {
          final byDate = (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          );
          return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
        });
      case _SortOrder.priceLowHigh:
        result.sort((a, b) => _byPriceThenName(a, b, 1));
      case _SortOrder.priceHighLow:
        result.sort((a, b) => _byPriceThenName(a, b, -1));
    }
    return result;
  }

  /// Dart's sort is not stable, so equal prices fall back to the name.
  static int _byPriceThenName(Product a, Product b, int direction) {
    final byPrice = a.price.compareTo(b.price) * direction;
    return byPrice != 0
        ? byPrice
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _category = null;
    });
  }

  Future<void> _refresh() async {
    await _store.load();
    if (mounted && _store.error != null) {
      showAppSnackBar(context, _store.error!.message, isError: true);
    }
  }

  void _openDetail(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          productId: product.id!,
          heroTag: 'product-${product.id}',
        ),
      ),
    );
  }

  /// Opens the create form. Called by the Add Product button in HomeShell.
  Future<void> addProduct() async {
    // A quick double tap must not open two forms.
    if (_opening) return;
    _opening = true;
    Product? saved;
    try {
      saved = await Navigator.of(context).push<Product>(
        MaterialPageRoute(builder: (_) => const ProductFormScreen()),
      );
    } finally {
      _opening = false;
    }
    if (saved != null && mounted) {
      final product = saved;
      showAppSnackBar(
        context,
        'Added "${product.name}".',
        action: SnackBarAction(
          label: 'View',
          onPressed: () => _openDetail(product),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            tooltip: _gridView ? 'Show as list' : 'Show as grid',
            onPressed: () => setState(() => _gridView = !_gridView),
            icon: Icon(
              _gridView ? Icons.view_list_outlined : Icons.grid_view_outlined,
            ),
          ),
          PopupMenuButton<_SortOrder>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: _SortOrder.name, child: Text('Name (A–Z)')),
              PopupMenuItem(
                value: _SortOrder.newest,
                child: Text('Newest first'),
              ),
              PopupMenuItem(
                value: _SortOrder.priceLowHigh,
                child: Text('Price: low to high'),
              ),
              PopupMenuItem(
                value: _SortOrder.priceHighLow,
                child: Text('Price: high to low'),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search name, brand or description',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            // Dropped when a landscape keyboard leaves too little room.
            if (constraints.maxHeight >= 200)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final category in Product.categories) ...[
                      FilterChip(
                        avatar: _category == category
                            ? null
                            : Icon(_categoryIcon(category), size: 18),
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (selected) => setState(
                          () => _category = selected ? category : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: ListenableBuilder(
                listenable: _store,
                builder: (context, _) => _content(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (!_store.hasLoaded) {
      if (_store.error != null) {
        return ErrorView(
          title: 'Could not load your products',
          message: _store.error!.message,
          onRetry: _store.load,
          showSettingsButton: true,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (_store.products.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 420,
              child: EmptyView(
                title: 'No products yet',
                message:
                    'Add your first product, or import one from the Explore tab.',
                action: FilledButton.icon(
                  onPressed: addProduct,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Product'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final products = _visible(_store.products);
    if (products.isEmpty) {
      return EmptyView(
        icon: Icons.search_off,
        title: 'No matches',
        message: 'No products match your search or filters.',
        action: TextButton(
          onPressed: _clearFilters,
          child: const Text('Clear filters'),
        ),
      );
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        _hasFilters
            ? 'Showing ${products.length} of ${pluralize(_store.products.length, 'product')}'
            : pluralize(products.length, 'product'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
    const padding = EdgeInsets.fromLTRB(16, 4, 16, 96);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: _gridView
          ? CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: padding.copyWith(bottom: 0),
                  sliver: SliverToBoxAdapter(child: header),
                ),
                SliverPadding(
                  padding: padding.copyWith(top: 0),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisExtent: 260,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                        ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return ProductGridCard(
                        key: ValueKey(product.id),
                        product: product,
                        heroTag: 'product-${product.id}',
                        onTap: () => _openDetail(product),
                      );
                    },
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: padding,
              itemCount: products.length + 1,
              separatorBuilder: (_, index) =>
                  SizedBox(height: index == 0 ? 0 : 8),
              itemBuilder: (context, index) {
                if (index == 0) return header;
                final product = products[index - 1];
                return ProductListTile(
                  key: ValueKey(product.id),
                  product: product,
                  heroTag: 'product-${product.id}',
                  onTap: () => _openDetail(product),
                );
              },
            ),
    );
  }

  static IconData _categoryIcon(String category) => switch (category) {
    'Laptop' => Icons.laptop_outlined,
    'Parts' => Icons.memory,
    _ => Icons.headphones_outlined,
  };
}
