import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/storage_keys.dart';

class GatewayConfig {
  final String backendUrl;
  final String gatewayToken;
  final String deviceCode;
  final bool autoStart;
  final int pollingIntervalSeconds;

  const GatewayConfig({
    required this.backendUrl,
    required this.gatewayToken,
    required this.deviceCode,
    required this.autoStart,
    required this.pollingIntervalSeconds,
  });

  bool get isComplete =>
      backendUrl.isNotEmpty && gatewayToken.isNotEmpty && deviceCode.isNotEmpty;

  GatewayConfig copyWith({
    String? backendUrl,
    String? gatewayToken,
    String? deviceCode,
    bool? autoStart,
    int? pollingIntervalSeconds,
  }) =>
      GatewayConfig(
        backendUrl: backendUrl ?? this.backendUrl,
        gatewayToken: gatewayToken ?? this.gatewayToken,
        deviceCode: deviceCode ?? this.deviceCode,
        autoStart: autoStart ?? this.autoStart,
        pollingIntervalSeconds: pollingIntervalSeconds ?? this.pollingIntervalSeconds,
      );
}

class LocalStorageService {
  final SharedPreferences _prefs;
  static const _uuid = Uuid();

  LocalStorageService(this._prefs);

  static Future<LocalStorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStorageService(prefs);
  }

  Future<GatewayConfig> readConfig() async {
    var deviceCode = _prefs.getString(StorageKeys.deviceCode) ?? '';
    if (deviceCode.isEmpty) {
      deviceCode = 'android-${_uuid.v4().substring(0, 8)}';
      await _prefs.setString(StorageKeys.deviceCode, deviceCode);
    }

    return GatewayConfig(
      backendUrl: _prefs.getString(StorageKeys.backendUrl) ?? '',
      gatewayToken: _prefs.getString(StorageKeys.gatewayToken) ?? '',
      deviceCode: deviceCode,
      autoStart: _prefs.getBool(StorageKeys.autoStart) ?? false,
      pollingIntervalSeconds: _prefs.getInt(StorageKeys.pollingIntervalSeconds) ?? 10,
    );
  }

  Future<void> saveConfig(GatewayConfig config) async {
    await _prefs.setString(StorageKeys.backendUrl, config.backendUrl.trim());
    await _prefs.setString(StorageKeys.gatewayToken, config.gatewayToken.trim());
    await _prefs.setString(StorageKeys.deviceCode, config.deviceCode.trim());
    await _prefs.setBool(StorageKeys.autoStart, config.autoStart);
    await _prefs.setInt(
      StorageKeys.pollingIntervalSeconds,
      config.pollingIntervalSeconds,
    );
  }

  Future<void> clear() async {
    await _prefs.remove(StorageKeys.backendUrl);
    await _prefs.remove(StorageKeys.gatewayToken);
    await _prefs.remove(StorageKeys.autoStart);
    await _prefs.remove(StorageKeys.pollingIntervalSeconds);
  }
}
