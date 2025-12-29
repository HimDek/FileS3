import "dart:io";
import "package:ini/ini.dart";
import "package:path_provider/path_provider.dart";

class IniManager {
  static late File _file;
  static Config? config;

  static Future<void> init() async {
    _file = File(
      '${(await getApplicationDocumentsDirectory()).path}/config.ini',
    );

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
