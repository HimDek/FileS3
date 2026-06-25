import 'package:path/path.dart' as p;
export 'package:path/path.dart';

class S3Context {
  p.Context get context => p.Context(style: p.Style.posix, current: '');

  String get separator => context.separator;

  bool isDir(String path) => path.endsWith(separator) || path.isEmpty;

  String asDir(String path) => isDir(path) ? path : '$path$separator';

  String normalize(String path) {
    String res = p.posix.normalize(path);
    return res == '.' ? '' : res;
  }

  String canonicalize(String path) {
    String res = p.posix.canonicalize(path);
    return res == '.' ? '' : res;
  }

  String absolute(String path) => context.absolute(path);

  String join(
    String part1, [
    String? part2,
    String? part3,
    String? part4,
    String? part5,
    String? part6,
    String? part7,
    String? part8,
    String? part9,
    String? part10,
    String? part11,
    String? part12,
    String? part13,
    String? part14,
    String? part15,
  ]) => context.join(
    part1,
    part2,
    part3,
    part4,
    part5,
    part6,
    part7,
    part8,
    part9,
    part10,
    part11,
    part12,
    part13,
    part14,
    part15,
  );

  String joinAll(List<String> paths) => context.joinAll(paths);

  List<String> split(String path) => context.split(path);

  String relative(String path, {String? from}) {
    String res = p.posix.relative(path, from: from);
    res = res == '.' ? '' : res;
    return isDir(path) ? asDir(res) : res;
  }

  String dirname(String path) {
    String res = p.posix.dirname(path);
    return res == '.' ? '' : asDir(res);
  }

  String basename(String path) =>
      isDir(path) ? asDir(p.posix.basename(path)) : p.posix.basename(path);

  String basenameWithoutExtension(String path) =>
      p.posix.basenameWithoutExtension(path);

  String extension(String path) => context.extension(path);

  bool isAbsolute(String path) => false;

  bool isRelative(String path) => true;

  bool isRootRelative(String path) => false;

  bool isWithin(String parent, String child) => context.isWithin(parent, child);

  bool equals(String path1, String path2) => context.equals(path1, path2);
}

final s3 = S3Context();

bool isDir(String path) =>
    path.endsWith('/') ||
    path.endsWith('\\') ||
    path.endsWith(p.separator) ||
    path.isEmpty;

String asDir(String path, {p.Context? context}) =>
    isDir(path) ? path : '$path${context?.separator ?? p.separator}';
