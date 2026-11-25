import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'data/cached_json_client.dart';
import 'data/open_prices_api.dart';
import 'data/product_scan_repository.dart';
import 'data/shopping_repository.dart';
import 'integration/gateways.dart';
import 'services/product_scan_service.dart';
import 'services/shopping_devices.dart';
import 'services/shopping_service.dart';
import 'viewmodels/budget_alert_center.dart';
import 'viewmodels/budget_view_model.dart';
import 'viewmodels/receipts_view_model.dart';
import 'viewmodels/shopping_lists_view_model.dart';

/// Branchement de la gestion 5 dans l'application.
///
/// Intégration : remplacer les passerelles de démo par les services réels des
/// gestions 1, 2 et 4 lors de l'appel à [createService].
class ShoppingModule {
  ShoppingModule._();

  static ShoppingService createService({
    required Database db,
    required UserGateway users,
    required ProductGateway products,
    required StoreGateway stores,
    AlertVibrator? vibrator,
    TokenStore? tokens,
    OpenPricesApi? api,
    DateTime Function()? clock,
  }) =>
      ShoppingService(
        repository: ShoppingRepository(db),
        prices: api ?? OpenPricesApi(cache: ShoppingApiCache(db)),
        users: users,
        products: products,
        stores: stores,
        vibrator: vibrator ?? DeviceAlertVibrator(),
        tokens: tokens ?? SecureTokenStore(),
        clock: clock,
      );

  /// Scan de produits (Open Food Facts + Open Prices), avec le même cache
  /// local que la gestion 5. [client] : remplaçable dans les tests.
  static ProductScanService createProductScan(ShoppingService service, {http.Client? client}) => ProductScanService(
        service,
        ProductScanRepository(
          client: CachedJsonClient(client: client, cache: ShoppingApiCache(service.repository.db)),
        ),
      );

  /// Observateur de navigation : le détail d'une liste n'écoute
  /// l'accéléromètre que lorsqu'il est l'écran visible.
  static final routeObserver = RouteObserver<ModalRoute<void>>();

  static List<SingleChildWidget> providers(
    ShoppingService service, {
    ReceiptReader? reader,
    ShakeSource? shakes,
    VoiceInput? voice,
    LiveCameraFactory? liveCamera,
    LocalNotifier? notifier,
    ProductScanService? productScan,
  }) =>
      [
        Provider<ShoppingService>.value(value: service),
        Provider<ShakeSource>(create: (_) => shakes ?? AccelerometerShakeSource()),
        Provider<VoiceInput>(create: (_) => voice ?? DeviceVoiceInput()),
        Provider<AlertVibrator>.value(value: service.vibrator),
        Provider<LocalNotifier>(create: (_) => notifier ?? DeviceLocalNotifier()),
        // Alertes de budget : bannière au-dessus de tous les écrans, ou
        // notification si l'app est en arrière-plan. Créé dès le démarrage.
        ChangeNotifierProvider<BudgetAlertCenter>(
          lazy: false,
          create: (c) => BudgetAlertCenter(service, c.read<LocalNotifier>()),
        ),
        // Une caméra par écran de scan en direct (ouverte puis libérée par l'écran).
        Provider<LiveCameraFactory>.value(value: liveCamera ?? DeviceLiveReceiptCamera.new),
        Provider<ProductScanService>(create: (_) => productScan ?? createProductScan(service)),
        Provider<ReceiptReader>(create: (_) => reader ?? MlKitReceiptReader()),
        ChangeNotifierProvider(create: (_) => ShoppingListsViewModel(service)..load()),
        ChangeNotifierProvider(create: (_) => ReceiptsViewModel(service)..load()),
        ChangeNotifierProvider(create: (_) => BudgetViewModel(service)),
        ChangeNotifierProvider(create: (_) => PriceAlertsViewModel(service)..load()),
      ];
}
