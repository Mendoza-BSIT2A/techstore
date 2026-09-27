import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/app_services.dart';
import '../services/product_store.dart';
import '../utils/format.dart';
import '../widgets/deal_card.dart';
import '../widgets/product_card.dart';
import '../widgets/product_image.dart';
import 'product_detail_screen.dart';
import 'settings_screen.dart';

/// Home tab: a live DummyJSON deal plus a summary of the custom database.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenTab});

  /// Switches the bottom navigation tab (1 = Inventory, 2 = Explore).
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppServices.productStore;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.storefront, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Flexible(
              child: Text('TechStore Hub', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Server settings',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Welcome back!', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your shop inventory and discover new tech.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const DealCard(),
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: 'Your inventory',
                      actionLabel: 'See all',
                      onAction: () => onOpenTab(1),
                    ),
                    const SizedBox(height: 8),
                    ListenableBuilder(
                      listenable: store,
                      builder: (context, _) => _InventorySummary(
                        store: store,
                        onSeeAll: () => onOpenTab(1),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ListenableBuilder(
                      listenable: store,
                      builder: (context, _) =>
                          _RecentlyAdded(products: store.recentlyAdded()),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.travel_explore),
                        title: const Text('Explore the DummyJSON catalog'),
                        subtitle: const Text(
                          'Browse live laptops, tablets and accessories',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => onOpenTab(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openDetail(BuildContext context, Product product) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProductDetailScreen(productId: product.id!),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _InventorySummary extends StatelessWidget {
  const _InventorySummary({required this.store, required this.onSeeAll});

  final ProductStore store;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!store.hasLoaded) {
      if (store.error != null) {
        return Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Custom API offline',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  store.error!.message,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: store.load,
                      child: const Text('Try again'),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                      child: const Text('Server settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final byCategory = store.countByCategory;
    final maxCount = byCategory.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.inventory_2_outlined,
                  value: formatNumber(store.products.length),
                  label: 'Products',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  icon: Icons.layers_outlined,
                  value: formatNumber(store.totalUnits),
                  label: 'Units in stock',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  icon: Icons.payments_outlined,
                  value: formatPrice(store.inventoryValue, cents: false),
                  label: 'Inventory value',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _StockAlerts(alerts: store.stockAlerts, onSeeAll: onSeeAll),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Products by category', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                for (final entry in byCategory.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: MediaQuery.textScalerOf(context).scale(92),
                          child: Text(
                            entry.key,
                            maxLines: 1,
                            softWrap: false,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: maxCount == 0 ? 0 : entry.value / maxCount,
                              minHeight: 10,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${entry.value}',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.onPrimaryContainer, size: 20),
            const SizedBox(height: 6),
            // Large amounts such as "$412,346" shrink instead of wrapping.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Products that are out of stock or running low, so the owner can reorder.
class _StockAlerts extends StatelessWidget {
  const _StockAlerts({required this.alerts, required this.onSeeAll});

  static const _maxShown = 5;

  final List<Product> alerts;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  alerts.isEmpty
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                  color: alerts.isEmpty
                      ? theme.colorScheme.primary
                      : theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stock alerts',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (alerts.isNotEmpty)
                  Text(pluralize(alerts.length, 'item'), style: muted),
              ],
            ),
            const SizedBox(height: 4),
            if (alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  'Every product has more than ${Product.lowStockLimit} units.',
                  style: muted,
                ),
              )
            else ...[
              Text(
                'Out of stock, or ${Product.lowStockLimit} units or fewer left.',
                style: muted,
              ),
              for (final product in alerts.take(_maxShown))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox.square(
                    dimension: 44,
                    child: ProductImage(
                      product.imageUrl,
                      iconSize: 20,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  title: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${product.category} · ${formatPrice(product.price)} · '
                    '${product.stock} left',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Capped so large text never lets the badge take the
                  // whole row (ListTile asserts on that).
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 112),
                    child: StockBadge(product: product),
                  ),
                  onTap: () => _openDetail(context, product),
                ),
              if (alerts.length > _maxShown)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onSeeAll,
                    child: Text('See all ${alerts.length} in Inventory'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentlyAdded extends StatelessWidget {
  const _RecentlyAdded({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader(title: 'Recently added'),
          const SizedBox(height: 8),
          SizedBox(
            height: 230,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final product = products[index];
                return SizedBox(
                  width: 160,
                  child: ProductGridCard(
                    key: ValueKey(product.id),
                    product: product,
                    onTap: () => _openDetail(context, product),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
