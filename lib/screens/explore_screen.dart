import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dummy_product.dart';
import '../services/app_services.dart';
import '../services/dummyjson_service.dart';
import '../utils/format.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';
import 'explore_product_screen.dart';

/// Explore tab: tech products from the DummyJSON API by category, with a
/// live search.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  String _category = DummyJsonService.techCategories.first;
  String _query = '';
  Timer? _debounce;
  late Future<List<DummyProduct>> _products = _fetch();

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool get _searching => _query.trim().isNotEmpty;

  /// GET /products/search when there is a query, else the chosen category.
  Future<List<DummyProduct>> _fetch({bool forceRefresh = false}) => _searching
      ? AppServices.dummyJson.search(_query)
      : AppServices.dummyJson.productsInCategory(
          _category,
          forceRefresh: forceRefresh,
        );

  Future<void> _reload() async {
    final future = _fetch(forceRefresh: true);
    setState(() {
      _products = future;
    });
    try {
      await future;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  void _selectCategory(String category) {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _category = category;
      _query = '';
      _products = _fetch();
    });
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    // Wait until the user stops typing before calling the API.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _products = _fetch();
      });
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _query = '';
      _products = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Explore Products')),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search DummyJSON tech products',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        ),
                ),
                onChanged: _onSearchChanged,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  setState(() {
                    _products = _fetch();
                  });
                },
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
                    for (final category in DummyJsonService.techCategories) ...[
                      ChoiceChip(
                        label: Text(DummyJsonService.categoryLabel(category)),
                        selected: !_searching && _category == category,
                        onSelected: (_) => _selectCategory(category),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: FutureBuilder<List<DummyProduct>>(
                future: _products,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ErrorView(
                      title: 'Could not reach DummyJSON',
                      message: '${snapshot.error}',
                      onRetry: _reload,
                    );
                  }
                  final products = snapshot.data ?? const [];
                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              _searching
                                  ? '${pluralize(products.length, 'result')} for "${_query.trim()}"'
                                  : '${pluralize(products.length, 'product')} · live from dummyjson.com',
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ),
                        if (products.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: EmptyView(
                              icon: Icons.search_off,
                              title: 'No matches',
                              message:
                                  'Try another search, e.g. "apple" or "laptop".',
                            ),
                          )
                        else
                          ListenableBuilder(
                            listenable: AppServices.productStore,
                            builder: (context, _) => SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              sliver: SliverGrid.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 200,
                                      mainAxisExtent: 236,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                    ),
                                itemCount: products.length,
                                itemBuilder: (context, index) {
                                  final product = products[index];
                                  final store = AppServices.productStore;
                                  return _ExploreTile(
                                    // Keyed by id so a filtered grid never reuses
                                    // another product's thumbnail.
                                    key: ValueKey(product.id),
                                    product: product,
                                    saved:
                                        store.byDummyId(product.id) != null ||
                                        store.byName(product.title) != null,
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreTile extends StatelessWidget {
  const _ExploreTile({super.key, required this.product, required this.saved});

  final DummyProduct product;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ExploreProductScreen(productId: product.id, initial: product),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(
                    product.coverImage,
                    fit: BoxFit.contain,
                    backgroundColor: Colors.white,
                    iconSize: 32,
                    semanticLabel: product.title,
                  ),
                  if (saved)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Tooltip(
                        message: 'In inventory',
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: theme.colorScheme.primary,
                          child: Icon(
                            Icons.check,
                            size: 18,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    product.brand.isEmpty
                        ? DummyJsonService.categoryLabel(product.category)
                        : product.brand,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatPrice(product.price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Colors.amber.shade700,
                      ),
                      const SizedBox(width: 2),
                      Text(product.rating.toStringAsFixed(1), style: muted),
                    ],
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
