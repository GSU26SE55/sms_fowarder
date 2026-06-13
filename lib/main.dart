import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/storage/local_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await LocalStorageService.create();
  runApp(SmsGatewayApp(storageService: storage));
}
