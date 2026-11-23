import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/meal_plan_view_model.dart';
import '../viewmodels/recipe_list_view_model.dart';
import '../viewmodels/recipe_stats_view_model.dart';
import 'recipe_list_screen.dart';
import 'recipe_stats_screen.dart';
import 'week_plan_screen.dart';

/// Accueil de la gestion 3 : recettes, planning de la semaine, statistiques.
class RecipesHomeScreen extends StatefulWidget {
  const RecipesHomeScreen({super.key});

  @override
  State<RecipesHomeScreen> createState() => _RecipesHomeScreenState();
}

class _RecipesHomeScreenState extends State<RecipesHomeScreen> {
  int _tab = 0;

  void _select(int i) {
    setState(() => _tab = i);
    // Les données d'un onglet ont pu changer depuis un autre.
    switch (i) {
      case 0:
        context.read<RecipeListViewModel>().load();
      case 1:
        context.read<MealPlanViewModel>().load();
      case 2:
        context.read<RecipeStatsViewModel>().load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: const [
          RecipeListScreen(),
          WeekPlanScreen(),
          RecipeStatsScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Recettes'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Planning'),
            NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Stats'),
          ],
        ),
      );
}
