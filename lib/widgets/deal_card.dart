import 'package:flutter/material.dart';

import '../models/dummy_product.dart';
import '../models/product.dart';
import '../screens/explore_product_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/product_form_screen.dart';
import '../services/app_services.dart';
import '../utils/format.dart';
import 'product_image.dart';
import 'state_views.dart';

/// Dashboard widget showing a random laptop or accessory from DummyJSON.
class DealCard extends StatefulWidget {
  const DealCard({super.key});

  @override
  State<DealCard> createState() => _DealCardState();
}

class _DealCardState extends State<DealCard> {
  late Future<DummyProduct> _deal = AppServices.dummyJson.randomDeal();
  int? _shownId;
  bool _opening = false;

  // A block body: an arrow `() => _deal = ...` would return the Future, which
  // setState rejects in debug builds.
  void _next() => setState(() {
    _deal = AppServices.dummyJson.randomDeal(excludeId: _shownId);
  });

  Future<void> _addToInventory(DummyProduct deal) async {
    // Ignore a second tap while the form is opening.
    if (_opening) return;
    _opening = true;
    try {
      final saved = await Navigator.of(context).push<Product>(
        MaterialPageRoute(builder: (_) => ProductFormScreen(prefill: deal)),
      );
      if (saved != null && mounted) {
        showAppSnackBar(context, 'Added "${saved.name}" to the inventory.');
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: FutureBuilder<DummyProduct>(
        future: _deal,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final deal = loading ? null : snapshot.data;
          _shownId = deal?.id ?? _shownId;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.local_offer_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                title: const Text('Deal of the Day'),
                subtitle: const Text('Live from the DummyJSON API'),
                trailing: IconButton(
                  tooltip: 'Show another deal',
                  onPressed: loading ? null : _next,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              // The error view gets its natural height so the retry button
              // is never clipped; the photo keeps a fixed aspect ratio.
              if (!loading && snapshot.hasError)
                ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: ErrorView(
                    title: 'No deal right now',
                    message: '${snapshot.error}',
                    onRetry: _next,
                  ),
                )
              else
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: deal == null
                      ? const ProductImage(null)
                      : GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ExploreProductScreen(
                                productId: deal.id,
                                initial: deal,
                              ),
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ProductImage(
                                deal.coverImage,
                                fit: BoxFit.contain,
                                backgroundColor: Colors.white,
                                semanticLabel: deal.title,
                              ),
                              if (deal.hasDiscount)
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: _DiscountBadge(deal: deal),
                                ),
                            ],
                          ),
                        ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Phones put the button under the title so long product
                    // names and large text sizes still fit.
                    final stacked =
                        constraints.maxWidth <
                        MediaQuery.textScalerOf(context).scale(420);
                    final info = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deal?.title ??
                              (loading
                                  ? 'Finding today\'s deal…'
                                  : 'No deal found'),
                          style: theme.textTheme.titleMedium,
                          maxLines: stacked ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (deal != null) ...[
                          const SizedBox(height: 2),
                          _DealPrice(deal: deal),
                        ],
                      ],
                    );
                    if (deal == null) return info;

                    final action = ListenableBuilder(
                      listenable: AppServices.productStore,
                      builder: (context, _) {
                        final store = AppServices.productStore;
                        final existing =
                            store.byDummyId(deal.id) ??
                            store.byName(deal.title);
                        if (existing != null) {
                          return TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ProductDetailScreen(
                                  productId: existing.id!,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('In inventory'),
                          );
                        }
                        return FilledButton.tonalIcon(
                          onPressed: () => _addToInventory(deal),
                          icon: const Icon(Icons.add),
                          label: const Text('Add to inventory'),
                        );
                      },
                    );

                    return stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              info,
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: action,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: info),
                              const SizedBox(width: 8),
                              action,
                            ],
                          );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DealPrice extends StatelessWidget {
  const _DealPrice({required this.deal});

  final DummyProduct deal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          formatPrice(deal.discountedPrice),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (deal.hasDiscount)
          Text(
            formatPrice(deal.price),
            style: muted?.copyWith(decoration: TextDecoration.lineThrough),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 16, color: Colors.amber.shade700),
            const SizedBox(width: 2),
            Text(deal.rating.toStringAsFixed(1), style: muted),
          ],
        ),
      ],
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.deal});

  final DummyProduct deal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '-${deal.discountPercentage.round()}%',
          style: TextStyle(color: scheme.onError, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
