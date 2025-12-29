import "dart:io";
import "package:ini/ini.dart";
import "package:path_provider/path_provider.dart";

class IniManager {
  static late File _file;
  static Config? config;

  static Future<void> init() async {
    if (Platform.isWindows) {
      _file = File('${Platform.environment['APPDATA']}\\FileS3\\config.ini');
    } else if (Platform.isLinux) {
      _file = File('/etc/files3/config.ini').existsSync()
          ? File('/etc/files3/config.ini')
          : File('${Platform.environment['HOME']}/.config/files3/config.ini');
    } else if (Platform.isMacOS) {
      _file = File(
        '${Platform.environment['HOME']}/Library/Application Support/FileS3/config.ini',
      );
    } else if (Platform.isAndroid) {
      _file = File(
        '${(await getApplicationDocumentsDirectory()).path}/config.ini',
      );
    }

    if (!_file.existsSync()) {
      _file.createSync(recursive: true);
      _file.writeAsStringSync('[aws]\n[s3]\n[directories]\n[modes]\n[ui]');
    }

    final lines = _file.readAsLinesSync();
    config = Config.fromStrings(lines);
  }

  static void save() {
    _file.writeAsStringSync(config.toString());
  }
}
