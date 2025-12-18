import 'dart:io';
import 'package:crypto/crypto.dart';

class HashUtil {
  static String md5Hash(File file) {
    final bytes = file.readAsBytesSync();
    return md5.convert(bytes).toString();
  }
}
