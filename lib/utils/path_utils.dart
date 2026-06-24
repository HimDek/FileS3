import 'package:path/path.dart' as p;
// ignore: implementation_imports
import 'package:path/src/style/posix.dart';

class S3Style extends PosixStyle {
  @override
  String get name => 's3';

  // Deprecated properties.

  @override
  Pattern get rootPattern => RegExp(r'^');

  @override
  int rootLength(String path, {bool withDrive = false}) => 0;

  @override
  String? getRoot(String path) => null;
}

String Function(String) convert = (String path) =>
    path.startsWith('./') || path.startsWith('.\\')
    ? path.substring(2)
    : path == '.' ||
          path == './' ||
          path == '.\\' ||
          path == '/' ||
          path == '\\'
    ? ''
    : path;

bool isDir(String path) =>
    path.endsWith('/') ||
    path.endsWith('\\') ||
    path.endsWith(p.separator) ||
    path.isEmpty;

String asDir(String path, {p.Context? context}) =>
    isDir(path) ? path : '$path${context?.separator ?? p.separator}';

String get separator => p.separator;

p.Context get s3 => p.Context(style: S3Style());

p.Context get context => p.context;

p.Context get posix => p.posix;

p.Context get windows => p.windows;

p.Context get url => p.url;

String normalize(String path) => p.normalize(path);

String canonicalize(String path) => p.canonicalize(path);

String absolute(String path) => p.absolute(path);

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
]) => p.join(
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

String joinAll(List<String> paths) => p.joinAll(paths);

List<String> split(String path) => p.split(path);

String relative(String path, {String? from}) => isDir(path)
    ? asDir(p.relative(path, from: from))
    : p.relative(path, from: from);

String dirname(String path) => asDir(p.dirname(path));

String basename(String path) =>
    isDir(path) ? asDir(p.basename(path)) : p.basename(path);

String basenameWithoutExtension(String path) =>
    p.basenameWithoutExtension(path);

String extension(String path) => p.extension(path);

bool isAbsolute(String path) => p.isAbsolute(path);

bool isRelative(String path) => p.isRelative(path);

bool isWithin(String parent, String child) => p.isWithin(parent, child);

bool equals(String path1, String path2) => p.equals(path1, path2);
