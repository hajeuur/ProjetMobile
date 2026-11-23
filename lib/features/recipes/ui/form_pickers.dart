import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'widgets.dart';

// ---------------------------------------------------------------------------
// Valeurs proposées dans les listes du formulaire
// ---------------------------------------------------------------------------

/// Une valeur proposée : ce qui est écrit dans le champ ([value]) et ce qui
/// est affiché dans la liste ([label]).
class ComboOption {
  const ComboOption(this.value, [String? label]) : label = label ?? value;
  final String value;
  final String label;
}

List<ComboOption> _numbers(Iterable<num> values, [String suffix = '']) =>
    [for (final v in values) ComboOption(formatDecimal(v.toDouble()), '${formatDecimal(v.toDouble())}$suffix')];

/// Temps de préparation (minutes).
final prepTimeOptions = _numbers(const [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 75, 90, 105, 120, 150, 180, 240], ' min');

/// Durée d'une étape (minutes).
final stepMinuteOptions =
    _numbers(const [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20, 25, 30, 35, 40, 45, 50, 60, 75, 90, 120, 150, 180], ' min');

/// Calories par portion : de 50 à 1500 kcal, par pas de 10.
final calorieOptions = _numbers([for (var k = 50; k <= 1500; k += 10) k], ' kcal');

/// Quantités d'un ingrédient (avec les fractions courantes).
final quantityOptions = _numbers(const [
  0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 75, 80, 100, 125, 150, 200, 250, 300,
  400, 500, 600, 750, 800, 1000, 1500, 2000,
]);

/// Unités reconnues par les conversions du stock et des calories
/// (voir `logic/units.dart`).
const unitOptions = [
  ComboOption('g', 'g — gramme'),
  ComboOption('kg', 'kg — kilogramme'),
  ComboOption('ml', 'ml — millilitre'),
  ComboOption('cl', 'cl — centilitre'),
  ComboOption('l', 'l — litre'),
  ComboOption('pièce'),
  ComboOption('cas', 'cas — cuillère à soupe'),
  ComboOption('cac', 'cac — cuillère à café'),
  ComboOption('tasse'),
  ComboOption('gousse'),
  ComboOption('tranche'),
  ComboOption('feuille'),
  ComboOption('pincée'),
  ComboOption('botte'),
  ComboOption('boîte'),
];

/// Catégories proposées même si aucune recette ne les utilise encore.
/// « Breakfast » est la valeur utilisée par TheMealDB et reconnue par le menu
/// automatique pour les petits-déjeuners.
const baseCategories = ['Plat', 'Entrée', 'Soupe', 'Salade', 'Breakfast', 'Dessert', 'Boisson'];

/// Catégories de base + celles déjà utilisées par les recettes de l'utilisateur
/// (ex. catégories TheMealDB), triées.
List<ComboOption> categoryOptions(Iterable<String> used) {
  final all = <String>{...baseCategories, ...used.where((c) => c.trim().isNotEmpty)}.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final c in all) ComboOption(c, c == 'Breakfast' ? 'Breakfast (petit-déjeuner)' : c)];
}

// ---------------------------------------------------------------------------
// Nombres : virgule ou point
// ---------------------------------------------------------------------------

/// Lit « 320,5 » ou « 320.5 ».
double? parseDecimal(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Lit un entier (« 30 », « 30,0 » acceptés ; « 30,5 » refusé).
int? parseWhole(String s) {
  final d = parseDecimal(s);
  return d != null && d == d.roundToDouble() ? d.round() : null;
}

/// Affiche une valeur décimale avec une virgule, sans « ,0 » inutile.
String formatDecimal(double v) {
  final s = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return s.replaceAll('.', ',');
}

String? validateDecimal(String? v) =>
    (v != null && v.trim().isNotEmpty && (parseDecimal(v) == null || parseDecimal(v)! < 0)) ? 'Nombre invalide' : null;

String? validateWhole(String? v) =>
    (v != null && v.trim().isNotEmpty && (parseWhole(v) == null || parseWhole(v)! < 0)) ? 'Nombre entier' : null;

// ---------------------------------------------------------------------------
// Champ « combo » : on tape OU on choisit dans la liste
// ---------------------------------------------------------------------------

/// Champ texte avec un bouton ▼ qui ouvre une liste de valeurs toutes prêtes.
/// On peut choisir dans la liste ou taper une autre valeur au clavier.
class ComboTextField extends StatelessWidget {
  const ComboTextField({
    super.key,
    required this.controller,
    required this.options,
    required this.label,
    this.keyboardType,
    this.validator,
    this.suffixText,
    this.helperText,
    this.dense = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final List<ComboOption> options;
  final String label;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final String? suffixText;
  final String? helperText;

  /// Version compacte pour les lignes d'ingrédients et d'étapes.
  final bool dense;
  final TextCapitalization textCapitalization;

  /// Position de la valeur actuelle dans la liste (ou de la plus proche pour un nombre).
  int _currentIndex() {
    final text = controller.text.trim();
    if (text.isEmpty) return -1;
    final exact = options.indexWhere((o) => o.value.toLowerCase() == text.toLowerCase());
    if (exact >= 0) return exact;
    final n = parseDecimal(text);
    if (n == null) return -1;
    final i = options.indexWhere((o) => (parseDecimal(o.value) ?? double.negativeInfinity) >= n);
    return i < 0 ? options.length - 1 : i;
  }

  Future<void> _openList(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final current = _currentIndex();
    final text = controller.text.trim().toLowerCase();
    const itemHeight = 48.0;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(label, style: Theme.of(c).textTheme.titleMedium),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              controller: ScrollController(initialScrollOffset: ((current - 2).clamp(0, options.length)) * itemHeight),
              itemExtent: itemHeight,
              itemCount: options.length,
              itemBuilder: (c, k) => ListTile(
                title: Text(options[k].label),
                selected: options[k].value.toLowerCase() == text,
                onTap: () => Navigator.pop(c, options[k].value),
              ),
            ),
          ),
        ]),
      ),
    );
    if (picked != null) controller.text = picked;
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          suffixText: suffixText,
          isDense: dense,
          border: dense ? null : const OutlineInputBorder(),
          suffixIconConstraints: dense ? const BoxConstraints(minWidth: 28, minHeight: 28) : null,
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_drop_down_circle_outlined),
            iconSize: dense ? 20 : 24,
            padding: dense ? EdgeInsets.zero : const EdgeInsets.all(8),
            constraints: dense ? const BoxConstraints(minWidth: 28, minHeight: 28) : null,
            visualDensity: dense ? VisualDensity.compact : null,
            tooltip: 'Choisir dans la liste',
            onPressed: () => _openList(context),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Photo : galerie / fichiers du PC / appareil photo
// ---------------------------------------------------------------------------

/// Choix de la photo : galerie (ou fichiers du PC sur Windows) ou appareil photo.
/// L'image choisie est copiée dans le dossier de l'application pour qu'elle
/// reste disponible même si l'original est supprimé. Renvoie son chemin.
Future<String?> pickRecipePhoto(BuildContext context) async {
  final picker = ImagePicker();
  final canUseCamera = picker.supportsImageSource(ImageSource.camera);
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_library),
          title: Text(Platform.isAndroid || Platform.isIOS ? 'Choisir dans la galerie' : 'Choisir une image sur l\'ordinateur'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera),
          title: const Text('Prendre une photo'),
          subtitle: canUseCamera ? null : const Text('Pas d\'appareil photo sur cet appareil'),
          enabled: canUseCamera,
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
      ]),
    ),
  );
  if (source == null) return null;

  try {
    final file = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null) return null;
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}recipe_photos');
    await dir.create(recursive: true);
    final dot = file.name.lastIndexOf('.');
    final ext = dot >= 0 ? file.name.substring(dot) : '.jpg';
    final target = '${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}$ext';
    await file.saveTo(target);
    return target;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Impossible de récupérer la photo : $e');
    return null;
  }
}

/// Aperçu de la photo avec les boutons Choisir / Retirer.
class PhotoField extends StatelessWidget {
  const PhotoField({super.key, required this.photo, required this.onChanged});

  final String? photo;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final has = photo != null && photo!.isNotEmpty;
    return Row(children: [
      RecipeImage(photo, size: 96),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.add_a_photo),
            label: Text(has ? 'Changer la photo' : 'Ajouter une photo'),
            onPressed: () async {
              final p = await pickRecipePhoto(context);
              if (p != null) onChanged(p);
            },
          ),
          if (has)
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Retirer la photo'),
              onPressed: () => onChanged(null),
            ),
        ]),
      ),
    ]);
  }
}
