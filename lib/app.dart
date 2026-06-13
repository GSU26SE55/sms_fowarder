import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/permissions/sms_permission_service.dart';
import 'core/storage/local_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/sms_gateway/native/native_sms_sender.dart';
import 'features/sms_gateway/presentation/controllers/gateway_settings_controller.dart';
import 'features/sms_gateway/presentation/controllers/sms_gateway_controller.dart';
import 'features/sms_gateway/presentation/pages/gateway_home_page.dart';

class SmsGatewayApp extends StatelessWidget {
  final LocalStorageService storageService;

  const SmsGatewayApp({super.key, required this.storageService});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );

    return MultiProvider(
      providers: [
        Provider<SmsPermissionService>(create: (_) => SmsPermissionService()),
        Provider<NativeSmsSender>(create: (_) => NativeSmsSender()),
        Provider<LocalStorageService>.value(value: storageService),
        ChangeNotifierProvider<GatewaySettingsController>(
          create: (_) => GatewaySettingsController(storageService),
        ),
        ChangeNotifierProvider<SmsGatewayController>(
          create: (ctx) => SmsGatewayController(
            permissionService: ctx.read<SmsPermissionService>(),
            nativeSmsSender: ctx.read<NativeSmsSender>(),
            storageService: storageService,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'SMS Gateway',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const GatewayHomePage(),
      ),
    );
  }
}
