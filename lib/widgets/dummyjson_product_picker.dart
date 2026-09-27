import 'package:flutter/material.dart';

import '../models/dummy_product.dart';
import '../services/app_services.dart';
import '../services/dummyjson_service.dart';
import '../utils/format.dart';
import 'product_image.dart';
import 'state_views.dart';

/// Bottom sheet listing the tech products (laptops, accessories, tablets,
/// smartphones) from the DummyJSON API.
/// Returns the chosen product, or null when dismissed.
Future<DummyProduct?> showDummyJsonProductPicker(
  BuildContext context, {
  int? selectedId,
}) {
  return showModalBottomSheet<DummyProduct>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _DummyJsonProductPicker(selectedId: selectedId),
  );
}

class _DummyJsonProductPicker extends StatefulWidget {
  const _DummyJsonProductPicker({this.selectedId});

  final int? selectedId;

  @override
  State<_DummyJsonProductPicker> createState() =>
      _DummyJsonProductPickerState();
}

class _DummyJsonProductPickerState extends State<_DummyJsonProductPicker> {
  late Future<List<DummyProduct>> _products = AppServices.dummyJson
      .allTechProducts();
  String _query = '';

  List<DummyProduct> _filter(List<DummyProduct> products) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return products;
    return products
        .where(
          (product) =>
              product.title.toLowerCase().contains(query) ||
              product.brand.toLowerCase().contains(query) ||
              DummyJsonService.categoryLabel(
                product.category,
              ).toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Sit above the keyboard so search results stay visible.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => LayoutBuilder(
          builder: (context, sheet) => Column(
            children: [
              // Dropped when a landscape keyboard leaves little room.
              if (sheet.maxHeight >= 140)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Link a DummyJSON product',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search products, e.g. macbook',
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<DummyProduct>>(
                  future: _products,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return ErrorView(
                        title: 'Could not load DummyJSON products',
                        message: '${snapshot.error}',
                        onRetry: () => setState(() {
                          _products = AppServices.dummyJson.allTechProducts(
                            forceRefresh: true,
                          );
                        }),
                      );
                    }
                    final products = _filter(snapshot.data ?? const []);
                    if (products.isEmpty) {
                      return const EmptyView(
                        icon: Icons.search_off,
                        title: 'No matches',
                        message: 'Try a different search term.',
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: products.length + 1,
                      itemBuilder: (context, index) {
                        // The explanation scrolls with the list, so the sheet
                        // never overflows on small screens with large text.
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: Text(
                              'Linking shows live ratings, warranty, shipping '
                              'and photos from dummyjson.com. Empty form fields '
                              'are filled in for you.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }
                        final product = products[index - 1];
                        final isSelected = product.id == widget.selectedId;
                        return ListTile(
                          // Keyed by id so a filtered list never shows another
                          // product's thumbnail while it loads.
                          key: ValueKey(product.id),
                          leading: SizedBox.square(
                            dimension: 48,
                            child: ProductImage(
                              product.coverImage,
                              fit: BoxFit.contain,
                              backgroundColor: Colors.white,
                              iconSize: 22,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          title: Text(
                            product.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              DummyJsonService.categoryLabel(product.category),
                              if (product.brand.isNotEmpty) product.brand,
                              formatPrice(product.price),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          selected: isSelected,
                          onTap: () => Navigator.of(context).pop(product),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
