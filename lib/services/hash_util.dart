import 'dart:io';
import 'package:crypto/crypto.dart';

class HashUtil {
  static Future<String> md5Hash(File file) async {
    final bytes = await file.readAsBytes();
    return md5.convert(bytes).toString();
  }
}
