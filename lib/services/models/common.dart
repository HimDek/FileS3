import 'package:files3/services/models/remote_file.dart';
import 'package:files3/services/job.dart';

class FileProps {
  final String key;
  final int size;
  final RemoteFile? file;
  final Job? job;

  FileProps({required this.key, required this.size, this.file, this.job});
}

enum SelectionAction { copy, cut, none }

enum SortMode {
  nameAsc,
  nameDesc,
  dateAsc,
  dateDesc,
  sizeAsc,
  sizeDesc,
  typeAsc,
  typeDesc,
}
