import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Drop-in replacement for `dart:developer`'s `log`.
///
/// `developer.log` only reaches an attached DevTools/VM-service client, so on a
/// phone running a sideloaded debug APK every tier failover was invisible in
/// `adb logcat`. This also mirrors the message to logcat (via [debugPrint])
/// in debug/profile builds so failures like `404 model not found` or
/// `App Check token invalid` are diagnosable with `adb logcat | grep navisense`.
void log(
  String message, {
  String name = '',
  Object? error,
  StackTrace? stackTrace,
}) {
  developer.log(message, name: name, error: error, stackTrace: stackTrace);
  if (kReleaseMode) return;
  final tag = name.isEmpty ? 'navisense' : name;
  debugPrint('[$tag] $message${error == null ? '' : ' | error: $error'}');
}
