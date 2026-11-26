import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/recipes/data/recipe_schema.dart';
import '../../features/shopping/data/shopping_schema.dart';

/// Base locale unique de l'application.
///
/// Chaque gestion déclare ses propres tables dans un fichier `*_schema.dart`
/// et l'ajoute ici. Pour intégrer une gestion : appeler son `create` dans
/// [_onCreate] et ses migrations dans [_onUpgrade], puis augmenter [version].
///
/// Versions : 1 = gestion 3 (Recettes) ; 2 = + gestion 5 (Courses et Budget) ;
/// 3 = format des produits sur les lignes de ticket (gestion 5, shrinkflation).
class AppDatabase {
  AppDatabase._();

  static const fileName = 'panier_malin.db';
  static const version = 3;

  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    return f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Gestion 3 — Recettes.
    await RecipeSchema.create(db);
    // Gestion 5 — Courses et Budget.
    await ShoppingSchema.create(db);
    // TODO(intégration) : UserSchema.create(db), ProductSchema.create(db), ...
  }

  static Future<void> _onUpgrade(Database db, int from, int to) async {
    await RecipeSchema.upgrade(db, from, to);
    await ShoppingSchema.upgrade(db, from, to);
  }
}
