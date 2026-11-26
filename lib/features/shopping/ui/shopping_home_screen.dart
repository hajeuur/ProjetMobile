import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/budget_view_model.dart';
import '../viewmodels/receipts_view_model.dart';
import '../viewmodels/shopping_lists_view_model.dart';
import 'budget_screen.dart';
import 'price_alerts_screen.dart';
import 'receipts_history_screen.dart';
import 'shopping_lists_screen.dart';

/// Accueil de la gestion 5 : listes, tickets, budget, alertes de prix.
class ShoppingHomeScreen extends StatefulWidget {
  const ShoppingHomeScreen({super.key});

  @override
  State<ShoppingHomeScreen> createState() => _ShoppingHomeScreenState();
}

class _ShoppingHomeScreenState extends State<ShoppingHomeScreen> {
  int _tab = 0;

  void _select(int i) {
    setState(() => _tab = i);
    // Les données d'un onglet ont pu changer depuis un autre (ticket validé…).
    switch (i) {
      case 0:
        context.read<ShoppingListsViewModel>().load();
      case 1:
        context.read<ReceiptsViewModel>().load();
      case 2:
        context.read<BudgetViewModel>().load();
      case 3:
        context.read<PriceAlertsViewModel>().load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: const [
          ShoppingListsScreen(),
          ReceiptsHistoryScreen(),
          BudgetScreen(),
          PriceAlertsScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Listes'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Tickets'),
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Budget'),
            NavigationDestination(icon: Icon(Icons.trending_up_outlined), selectedIcon: Icon(Icons.trending_up), label: 'Prix'),
          ],
        ),
      );
}
