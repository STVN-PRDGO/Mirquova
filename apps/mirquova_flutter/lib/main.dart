import 'package:flutter/material.dart';

import 'adapters/native_discovery.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MirquovaApp(discovery: NativeDiscovery()));
}
