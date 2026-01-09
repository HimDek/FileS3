import 'dart:io';
import 'dart:convert';
import 'package:ini/ini.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/hash_util.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/models.dart';

Future<int?> Function(BuildContext) expiryDialog = (BuildContext context) =>
    showDialog<int>(
      context: context,
      builder: (_) {
        int d = 0, h = 1;
        return StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: const Text('Select Validity Duration'),
            content: Row(
              children: [
                DropdownButton<int>(
                  value: d,
                  items: List.generate(
                    31,
                    (i) => DropdownMenuItem(value: i, child: Text('$i d')),
                  ),
                  onChanged: (v) => set(() => d = v!),
                ),
                DropdownButton<int>(
                  value: h,
                  items: List.generate(
                    24,
                    (i) => DropdownMenuItem(value: i, child: Text('$i h')),
                  ),
                  onChanged: (v) => set(() => h = v!),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: d * 86400 + h * 3600 == 0
                    ? null
                    : () => Navigator.pop(c, d * 86400 + h * 3600),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );

Future<String?> Function(BuildContext, String) renameDialog =
    (BuildContext context, String currentName) => showDialog<String>(
      context: context,
      builder: (_) {
        TextEditingController controller = TextEditingController(
          text: currentName,
        );
        return StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: const Text('Rename File'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'New Name'),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(c, controller.text.trim()),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );

String bytesToReadable(int bytes) {
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(2)} ${suffixes[i]}';
}

String _monthToString(int month) {
  return [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];
}

String timeToReadable(DateTime time) {
  final localTime = time.toLocal();
  final diff = DateTime.now().toLocal().difference(localTime);
  if (diff.inSeconds < 60) {
    return '${diff.inSeconds}s ago';
  } else if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  return "${localTime.day.toString().padLeft(2, '0')} ${_monthToString(localTime.month)} ${localTime.year} ${(localTime.hour % 12).toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')} ${localTime.hour >= 12 ? 'PM' : 'AM'}";
}

List<FileProps> sort(
  Iterable<FileProps> items,
  SortMode sortMode,
  bool foldersFirst,
) {
  List<FileProps> sortedItems = List.from(items);
  sortedItems.sort((a, b) {
    var aIsDir = a.key.endsWith('/');
    var bIsDir = b.key.endsWith('/');

    if (foldersFirst) {
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
    }

    switch (sortMode) {
      case SortMode.nameAsc:
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      case SortMode.nameDesc:
        return b.key.toLowerCase().compareTo(a.key.toLowerCase());
      case SortMode.dateAsc:
        DateTime aDate = a.file != null
            ? a.file!.lastModified!
            : DateTime.fromMillisecondsSinceEpoch(0);
        DateTime bDate = b.file != null
            ? b.file!.lastModified!
            : DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      case SortMode.dateDesc:
        DateTime aDate = a.file != null
            ? a.file!.lastModified!
            : DateTime.fromMillisecondsSinceEpoch(0);
        DateTime bDate = b.file != null
            ? b.file!.lastModified!
            : DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      case SortMode.sizeAsc:
        return a.size.compareTo(b.size);
      case SortMode.sizeDesc:
        return b.size.compareTo(a.size);
      case SortMode.typeAsc:
        String aExt = a.key.contains('.')
            ? a.key.split('.').last.toLowerCase()
            : '';
        String bExt = b.key.contains('.')
            ? b.key.split('.').last.toLowerCase()
            : '';
        return aExt.compareTo(bExt);
      case SortMode.typeDesc:
        String aExt = a.key.contains('.')
            ? a.key.split('.').last.toLowerCase()
            : '';
        String bExt = b.key.contains('.')
            ? b.key.split('.').last.toLowerCase()
            : '';
        return bExt.compareTo(aExt);
    }
  });
  return sortedItems;
}

void renameOrCopyAndDelete(File file, String newPath) {
  try {
    file.renameSync(newPath);
  } catch (e) {
    file.copySync(newPath);
    file.deleteSync();
  }
}

class ThemeController extends ChangeNotifier {
  ThemeMode _theme = ThemeMode.system;

  ThemeMode get theme => _theme;

  ThemeMode get themeMode {
    switch (_theme) {
      case ThemeMode.light:
        return ThemeMode.light;
      case ThemeMode.dark:
        return ThemeMode.dark;
      case ThemeMode.system:
        return ThemeMode.system;
    }
  }

  void update(ThemeMode theme) {
    _theme = theme;
    notifyListeners();
  }
}

class UltraDarkController extends ChangeNotifier {
  bool _ultraDark = false;

  bool get ultraDark => _ultraDark;

  void update(bool ultraDark) {
    _ultraDark = ultraDark;
    notifyListeners();
  }
}

final themeController = ThemeController();
final ultraDarkController = UltraDarkController();

abstract class IniManager {
  static late File _file;
  static Config? config;

  static void init() {
    _file = File('${Main.documentsDir}/config.ini');

    if (!_file.existsSync()) {
      _file.createSync(recursive: true);
      _file.writeAsStringSync(
        '[profiles]\n[directories]\n[modes]\n[ui]\n[download]',
      );
    }

    final lines = _file.readAsLinesSync();
    config = Config.fromStrings(lines);
    cleanDirectories();
  }

  static void save() {
    _file.writeAsStringSync(config.toString());
  }

  static void cleanDirectories({String? keepKey}) {
    for (String key in config!.options('directories')?.toList() ?? []) {
      final dirPath = config!.get('directories', key).toString();
      for (String k in config!.options('directories')?.toList() ?? []) {
        if (k != key &&
            p.canonicalize(config!.get('directories', k).toString()) ==
                p.canonicalize(dirPath)) {
          if (keepKey != k) {
            config!.removeOption('directories', k);
          }
          if (keepKey != key) {
            config!.removeOption('directories', key);
          }
        }
      }
    }
  }
}

abstract class ConfigManager {
  static bool initialized = false;
  static const _storage = FlutterSecureStorage();

  static Future<void> init() async {
    if (!initialized || IniManager.config == null) {
      if (IniManager.config == null) {
        IniManager.init();
      }
      await _migrateIfNeeded();
      initialized = true;
    }
  }

  static bool _is_1_0() {
    return IniManager.config!.sections().contains('aws') &&
        IniManager.config!.sections().contains('s3');
  }

  static bool _is_1_1() {
    return IniManager.config!.sections().contains('profiles');
  }

  // ignore: non_constant_identifier_names
  static Future<void> _migrate_1_0_to_1_1() async {
    final legacyAccessKey = await _storage.read(key: 'aws_access_key') ?? '';
    final legacySecretKey = await _storage.read(key: 'aws_secret_key') ?? '';

    final legacyRegion = IniManager.config?.get('aws', 'region') ?? '';
    final legacyBucket = IniManager.config?.get('s3', 'bucket') ?? '';
    final legacyPrefix = IniManager.config?.get('s3', 'prefix') ?? '';
    final legacyHost = IniManager.config?.get('s3', 'host') ?? '';

    if (legacyAccessKey.isNotEmpty && legacySecretKey.isNotEmpty) {
      final defaultConfig = S3Config(
        accessKey: legacyAccessKey,
        secretKey: legacySecretKey,
        region: legacyRegion,
        bucket: legacyBucket,
        prefix: legacyPrefix,
        host: legacyHost,
      );
      await saveS3Config('default', defaultConfig);
      await _storage.delete(key: 'aws_access_key');
      await _storage.delete(key: 'aws_secret_key');
      IniManager.config!.removeSection('aws');
      IniManager.config!.removeSection('s3');
      IniManager.save();
    }
  }

  static Future<void> _migrateIfNeeded() async {
    if (!_is_1_1() && _is_1_0()) {
      await _migrate_1_0_to_1_1();
    }
  }

  static Future<Map<String, S3Config>> loadS3Config() async {
    Map<String, S3Config> configs = {};
    for (String profileName in IniManager.config?.options('profiles') ?? []) {
      final accessKey =
          await _storage.read(key: 'aws_access_key_$profileName') ?? '';
      final secretKey =
          await _storage.read(key: 'aws_secret_key_$profileName') ?? '';
      final config = IniManager.config?.get('profiles', profileName) ?? '';
      final parts = config.split('|');
      final region = parts.isNotEmpty ? parts[0] : '';
      final bucket = parts.length > 1 ? parts[1] : '';
      final prefix = parts.length > 2 ? parts[2] : '';
      final host = parts.length > 3 ? parts[3] : '';
      configs[profileName] = S3Config(
        accessKey: accessKey,
        secretKey: secretKey,
        region: region,
        bucket: bucket,
        prefix: prefix,
        host: host,
      );
    }
    return configs;
  }

  static Future<void> saveS3Config(String name, S3Config config) async {
    if (!IniManager.config!.sections().contains("profiles")) {
      IniManager.config!.addSection("profiles");
    }
    final profileStr =
        '${config.region}|${config.bucket}|${config.prefix}|${config.host}';
    IniManager.config!.set("profiles", name, profileStr);
    await _storage.write(key: 'aws_access_key_$name', value: config.accessKey);
    await _storage.write(key: 'aws_secret_key_$name', value: config.secretKey);
    IniManager.save();
  }

  static UiConfig loadUiConfig() {
    final colorModeStr = IniManager.config?.get("ui", "color_mode") ?? 'system';
    final ultraDarkStr = IniManager.config?.get("ui", "ultra_dark") ?? 'false';

    final colorMode = switch (colorModeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final ultraDark = ultraDarkStr.toLowerCase() == 'true';

    return UiConfig(colorMode: colorMode, ultraDark: ultraDark);
  }

  static Future<void> saveUiConfig(UiConfig config) async {
    final colorModeStr = switch (config.colorMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

    if (!IniManager.config!.sections().contains("ui")) {
      IniManager.config!.addSection("ui");
    }
    IniManager.config!.set("ui", "color_mode", colorModeStr);
    IniManager.config!.set("ui", "ultra_dark", config.ultraDark.toString());
    IniManager.save();
  }

  static TransferConfig loadTransferConfig() {
    final maxConcurrentTransfersStr =
        IniManager.config?.get("transfer", "max_concurrent_transfers") ?? '5';

    final maxConcurrentTransfers = int.tryParse(maxConcurrentTransfersStr) ?? 5;

    return TransferConfig(maxConcurrentTransfers: maxConcurrentTransfers);
  }

  static Future<void> saveTransferConfig(TransferConfig config) async {
    if (!IniManager.config!.sections().contains("transfer")) {
      IniManager.config!.addSection("transfer");
    }
    IniManager.config!.set(
      "transfer",
      "max_concurrent_transfers",
      config.maxConcurrentTransfers.toString(),
    );
    IniManager.save();
  }

  static Future<void> saveRemoteFiles(List<RemoteFile> files) async {
    final String jsonString = jsonEncode(
      files.map((file) => file.toJson()).toList(),
    );
    await _storage.write(key: 'remote_files', value: jsonString);
  }

  static Future<List<RemoteFile>> loadRemoteFiles() async {
    final jsonString = await _storage.read(key: 'remote_files') ?? '[]';
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList
        .map((json) => RemoteFile.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

class DeletionRegistrar {
  final Profile profile;
  late File _file;
  late String _key;
  Config? _config;
  DateTime _lastPulled = DateTime.fromMillisecondsSinceEpoch(0).toUtc();

  DeletionRegistrar({required this.profile}) {
    _key = '${profile.name}/deletion-register.ini';
    _file = File('${Main.documentsDir}/$_key');

    if (!_file.existsSync()) {
      _file.createSync(recursive: true);
      _file.writeAsStringSync('[register]');
    }

    _config = Config.fromStrings(_file.readAsLinesSync());
  }

  void save() {
    _file.writeAsStringSync(_config.toString());
  }

  void logDeletions(List<String> keys) {
    if (!_config!.sections().contains('register')) {
      _config!.addSection('register');
    }
    for (String key in keys) {
      _config!.set('register', key, DateTime.now().toUtc().toIso8601String());
    }
    save();
  }

  Future<Map<String, DateTime>> pullDeletions() async {
    await profile.refreshRemote(dir: _key);

    if (Main.remoteFiles.every((file) => file.key != _key)) {
      if (kDebugMode) {
        debugPrint("Remote deletion register does not exist.");
      }
      return {};
    }

    final remoteFile = Main.remoteFiles.firstWhere((file) => file.key == _key);

    if (_lastPulled.toUtc().isAfter(
          remoteFile.lastModified?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
        ) &&
        _file.existsSync()) {
      if (kDebugMode) {
        debugPrint("Local deletion register is up to date.");
      }
      return {
        for (var entry in _config!.options('register')!)
          entry: DateTime.parse(_config!.get('register', entry)!).toUtc(),
      };
    }

    Job job = DownloadJob(
      localFile: _file,
      remoteKey: _key,
      bytes: remoteFile.size,
      md5: () {
        final hex = remoteFile.etag.replaceAll('"', '');

        if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(hex)) {
          throw StateError('ETag is not a single-part MD5 digest');
        }

        final bytes = List<int>.generate(
          16,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
        );

        return Digest(bytes);
      }(),
      profile: profile,
      onStatus: (job, result) {},
    );

    await job.start();
    Job.jobs.remove(job);

    if (_file.existsSync()) {
      _config = Config.fromStrings(_file.readAsLinesSync());
    }

    _lastPulled = DateTime.now().toUtc();

    return {
      for (var entry in _config!.options('register')!)
        entry: DateTime.parse(_config!.get('register', entry)!).toUtc(),
    };
  }

  Future<void> pushDeletions() async {
    Job job = UploadJob(
      localFile: _file,
      remoteKey: _key,
      bytes: _file.lengthSync(),
      onStatus: (job, result) {},
      md5: await HashUtil(_file).md5Hash(),
      profile: profile,
    );
    await job.start();
    Job.jobs.remove(job);
  }
}
