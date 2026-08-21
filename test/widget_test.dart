// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:app_manager/adb_manager.dart';

void main() {
  test('DeviceInfo display name test', () {
    final dev = DeviceInfo(
      serial: 'ZY227G3GD8',
      state: 'device',
      model: 'Pixel_7',
      product: 'panther',
      isWifi: false,
    );
    expect(dev.displayName, 'Pixel_7 [Android 11] (ZY227G3GD8)');
    expect(dev.isWifi, false);
  });

  test('AppPackageInfo app name parsing test', () {
    final pkg = AppPackageInfo(
      packageName: 'com.example.chat',
      apkPath: '/data/app/chat.apk',
      isSystem: false,
      isDisabled: false,
    );
    expect(pkg.appName, 'Chat');
  });
}
