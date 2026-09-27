import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/app_services.dart';
import 'dashboard_screen.dart';
import 'explore_screen.dart';
import 'product_list_screen.dart';

/// Top-level navigation: bottom bar on phones, side rail on wide screens.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Keeps each tab's state (search text, scroll position…) when the layout
  /// switches between bottom bar and side rail, e.g. on rotation.
  final _pagesKey = GlobalKey();
  final _productListKey = GlobalKey<ProductListScreenState>();

  static const _destinations = [
    (icon: Icons.home_outlined, selected: Icons.home, label: 'Home'),
    (
      icon: Icons.inventory_2_outlined,
      selected: Icons.inventory_2,
      label: 'Inventory',
    ),
    (
      icon: Icons.travel_explore_outlined,
      selected: Icons.travel_explore,
      label: 'Explore',
    ),
  ];

  @override
  void initState() {
    super.initState();
    AppServices.productStore.load();
    ApiConfig.baseUrl.addListener(_onServerChanged);
  }

  @override
  void dispose() {
    ApiConfig.baseUrl.removeListener(_onServerChanged);
    super.dispose();
  }

  void _onServerChanged() => AppServices.productStore
    ..reset()
    ..load();

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      key: _pagesKey,
      index: _index,
      children: [
        DashboardScreen(onOpenTab: _select),
        ProductListScreen(key: _productListKey),
        const ExploreScreen(),
      ],
    );

    // Lives on this outer Scaffold so SnackBars (shown here) move it up
    // instead of covering it.
    final addButton = _index == 1
        ? FloatingActionButton.extended(
            key: const Key('add_product'),
            onPressed: () => _productListKey.currentState?.addProduct(),
            icon: const Icon(Icons.add),
            label: const Text('Add Product'),
          )
        : null;

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return Scaffold(
            floatingActionButton: addButton,
            body: Row(
              children: [
                if (wide) ...[
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    scrollable: true,
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selected),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                ],
                Expanded(child: pages),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    destinations: [
                      for (final d in _destinations)
                        NavigationDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selected),
                          label: d.label,
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
