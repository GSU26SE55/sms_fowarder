import 'package:flutter/foundation.dart';

import '../../../../core/storage/local_storage_service.dart';

class GatewaySettingsController extends ChangeNotifier {
  final LocalStorageService _storage;

  GatewayConfig _config = const GatewayConfig(
    backendUrl: '',
    gatewayToken: '',
    deviceCode: '',
    autoStart: false,
    pollingIntervalSeconds: 10,
  );

  GatewaySettingsController(this._storage);

  GatewayConfig get config => _config;

  Future<void> load() async {
    _config = await _storage.readConfig();
    notifyListeners();
  }

  Future<void> save(GatewayConfig newConfig) async {
    await _storage.saveConfig(newConfig);
    _config = newConfig;
    notifyListeners();
  }
}
