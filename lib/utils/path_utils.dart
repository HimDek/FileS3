import 'package:path/path.dart' as p;

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

bool Function(String) isDir = (String path) =>
    path.endsWith('/') || path.endsWith('\\');

String Function(String) asDir = (String path) =>
    isDir(path) ? path : '$path${p.separator}';

String get separator => p.separator;

String Function(String) context = p.context.normalize;

String Function(String) posix = p.posix.normalize;

String Function(String) windows = p.windows.normalize;

String Function(String) url = p.url.normalize;

String Function(String) normalize = p.normalize;

String Function(String) s3 = (String path) => convert(
  isDir(path) ? asDir(p.posix.normalize(path)) : p.posix.normalize(path),
);

String Function(String) canonicalize = p.canonicalize;

String Function(String) absolute = p.absolute;

String Function(String, String?) join = p.join;

String Function(List<String>) joinAll = p.joinAll;

List<String> Function(String) split = p.split;

String Function(String, {String? from}) relative =
    (String path, {String? from}) => isDir(path)
    ? asDir(p.relative(path, from: from))
    : p.relative(path, from: from);

String Function(String) dirname = (String path) => asDir(p.dirname(path));

String Function(String) basename = (String path) =>
    isDir(path) ? asDir(p.basename(path)) : p.basename(path);

String Function(String) basenameWithoutExtension = p.basenameWithoutExtension;

String Function(String) extension = p.extension;

bool Function(String) isAbsolute = p.isAbsolute;

bool Function(String) isRelative = p.isRelative;

bool Function(String parent, String child) isWithin = p.isWithin;
