import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';

class _PathMutex {
  Future<void> _tail = Future.value();

  Future<T> synchronized<T>(Future<T> Function() task) {
    final run = _tail.then((_) => task());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }
}

class HashUtil {
  static final Map<String, _PathMutex> _locks = {};

  static _PathMutex _mutexFor(String path) =>
      _locks.putIfAbsent(path, () => _PathMutex());

  final File file;

  HashUtil(this.file);

  Future<Digest> md5Hash() {
    return _mutexFor(
      file.path,
    ).synchronized(() => md5.bind(file.openRead()).single);
  }
}
