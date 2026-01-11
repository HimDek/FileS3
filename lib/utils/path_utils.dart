import 'package:path/path.dart' as p;

String Function(String) convert = (String path) =>
    path.startsWith('./') || path.startsWith('.\\')
    ? path.substring(2)
    : path == '.'
    ? ''
    : path;

bool Function(String) isDir = (String path) =>
    path.endsWith('/') || path.endsWith('\\');

String separator = p.separator;

String Function(String) context = p.context.normalize;

String Function(String) posix = p.posix.normalize;

String Function(String) windows = p.windows.normalize;

String Function(String) url = p.url.normalize;

String Function(String) normalize = p.normalize;

String Function(String) canonicalize = p.canonicalize;

String Function(String) absolute = p.absolute;

String Function(String, String?) join = p.join;

String Function(List<String>) joinAll = p.joinAll;

List<String> Function(String) split = p.split;

String relative(String path, {String? from}) =>
    convert(p.relative(path, from: from));

String dirname(String path) => convert('${p.dirname(path)}${p.separator}');

String Function(String) basename = p.basename;

String Function(String) basenameWithoutExtension = p.basenameWithoutExtension;

String Function(String) extension = p.extension;

bool Function(String) isAbsolute = p.isAbsolute;

bool Function(String) isRelative = p.isRelative;

bool Function(String, String) isWithin = p.isWithin;
