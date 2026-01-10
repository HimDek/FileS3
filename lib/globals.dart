import 'package:flutter/material.dart';

GlobalKey globalKey = GlobalKey();
BuildContext? get globalContext => globalKey.currentContext;
ScaffoldMessengerState? get globalScaffoldMessenger =>
    globalContext == null ? null : ScaffoldMessenger.of(globalContext!);
NavigatorState? get globalNavigator =>
    globalContext == null ? null : Navigator.of(globalContext!);
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

const Map<String, Map<String, String>> awsRegions =
    <String, Map<String, String>>{
      'United States': {
        'us-east-1': 'N. Virginia',
        'us-east-2': 'Ohio',
        'us-west-1': 'N. California',
        'us-west-2': 'Oregon',
      },
      'Africa:': {'af-south-1': 'Cape Town'},
      'Asia Pacific': {
        'ap-east-1': 'Hong Kong',
        'ap-east-2': 'Taipei',
        'ap-northeast-1': 'Tokyo',
        'ap-northeast-2': 'Seoul',
        'ap-northeast-3': 'Osaka',
        'ap-south-1': 'Mumbai',
        'ap-south-2': 'Hyderabad',
        'ap-southeast-1': 'Singapore',
        'ap-southeast-2': 'Sydney',
        'ap-southeast-3': 'Jakarta',
        'ap-southeast-4': 'Melbourne',
        'ap-southeast-5': 'Malaysia',
        'ap-southeast-6': 'Kuala Lumpur',
        'ap-southeast-7': 'Ho Chi Minh City',
      },
      'Canada:': {'ca-central-1': 'Central', 'ca-west-1': 'Calgary'},
      'Europe:': {
        'eu-central-1': 'Frankfurt',
        'eu-central-2': 'Zurich',
        'eu-north-1': 'Stockholm',
        'eu-south-1': 'Milan',
        'eu-south-2': 'Spain',
        'eu-west-1': 'Ireland',
        'eu-west-2': 'London',
        'eu-west-3': 'Paris',
      },
      'Middle East:': {'me-central-1': 'UAE', 'me-south-1': 'Bahrain'},
      'Israel': {'il-central-1': 'Tel Aviv'},
      'South America:': {'sa-east-1': 'São Paulo'},
      'China:': {
        'cn-north-1': 'Beijing',
        'cn-northwest-1': 'Ningxia',
        'cn-south-1': 'Guangzhou',
      },
    };
