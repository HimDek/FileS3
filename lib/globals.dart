import 'package:flutter/material.dart';

GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
BuildContext? get globalContext => navigatorKey.currentContext;
ScaffoldMessengerState? get globalScaffoldMessenger =>
    globalContext == null ? null : ScaffoldMessenger.of(globalContext!);
NavigatorState? get globalNavigator => navigatorKey.currentState;
ThemeData? get globalTheme =>
    globalContext == null ? null : Theme.of(globalContext!);

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showSnackBar(
  SnackBar snackBar,
) {
  if (globalScaffoldMessenger != null) {
    return globalScaffoldMessenger!.showSnackBar(snackBar);
  }
  return null;
}

Future<T?>? pushRoute<T>(Route<T> route) {
  if (globalNavigator != null) {
    return globalNavigator!.push(route);
  }
  return null;
}
