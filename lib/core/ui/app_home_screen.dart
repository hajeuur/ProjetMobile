import 'package:flutter/material.dart';

import '../../features/recipes/ui/recipes_home_screen.dart';
import '../../features/shopping/ui/shopping_home_screen.dart';

/// Accueil de PanierMalin : une entrée par gestion. Les gestions pas encore
/// intégrées dans ce dépôt sont affichées grisées.
class AppHomeScreen extends StatelessWidget {
  const AppHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String, IconData, Widget?)>[
      ('Courses et Budget', 'Listes, tickets de caisse, budget du mois, alertes de prix', Icons.shopping_cart, const ShoppingHomeScreen()),
      ('Recettes', 'Recettes, planning de la semaine, mode cuisine', Icons.menu_book, const RecipesHomeScreen()),
      ('Utilisateurs et Foyer', 'Gestion 1 — à intégrer', Icons.people_outline, null),
      ('Produits et Stock', 'Gestion 2 — à intégrer', Icons.inventory_2_outlined, null),
      ('Magasins', 'Gestion 4 — à intégrer', Icons.storefront_outlined, null),
      ('Activité et Santé', 'Gestion 6 — à intégrer', Icons.directions_walk, null),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('PanierMalin')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final (title, subtitle, icon, screen) in entries)
          Card(
            child: ListTile(
              enabled: screen != null,
              leading: Icon(icon, size: 32),
              title: Text(title, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(subtitle),
              trailing: screen == null ? null : const Icon(Icons.chevron_right),
              onTap: screen == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
            ),
          ),
      ]),
    );
  }
}
