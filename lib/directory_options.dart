import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'services/models/backup_mode.dart';

class DirectoryOptions extends StatefulWidget {
  final String directory;
  final Function(String) onDelete;

  const DirectoryOptions({
    super.key,
    required this.directory,
    required this.onDelete,
  });

  @override
  DirectoryOptionsState createState() => DirectoryOptionsState();
}

class DirectoryOptionsState extends State<DirectoryOptions> {
  static const storage = FlutterSecureStorage();
  String? local = null;
  late int? mode = 1;

  void getLocal() async {
    local = await storage.read(key: widget.directory);
    mode = int.tryParse(
      await storage.read(key: 'mode_${widget.directory}') ?? '1',
    );
    setState(() {});
  }

  void setLocal(String dir) async {
    await storage.write(key: widget.directory, value: dir);
    getLocal();
  }

  void setMode(int newMode) async {
    await storage.write(
      key: 'mode_${widget.directory}',
      value: newMode.toString(),
    );
    getLocal();
  }

  @override
  void initState() {
    super.initState();
    getLocal();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Text(
            'Options for ${widget.directory}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 24),
        ListTile(
          leading: const Icon(Icons.drive_folder_upload),
          title: const Text('Backup From'),
          subtitle: Text(local ?? 'Not set'),
          onTap: () async {
            final String? directoryPath = await getDirectoryPath();
            if (directoryPath != null) {
              setLocal(directoryPath);
            }
          },
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Backup Mode'),
        ),
        RadioListTile(
          value: BackupMode.upload.value,
          title: Text(BackupMode.upload.name),
          subtitle: Text(BackupMode.upload.description),
          dense: true,
          groupValue: mode,
          onChanged: (s) {
            setMode(s!);
          },
        ),
        RadioListTile(
          value: BackupMode.sync.value,
          title: Text(BackupMode.sync.name),
          subtitle: Text(BackupMode.sync.description),
          dense: true,
          groupValue: mode,
          onChanged: (s) {
            setMode(s!);
          },
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.delete),
          title: Text('Delete'),
          onTap: () async {
            bool yes =
                await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Directory'),
                    content: Text(
                      'Are you sure you want to delete ${widget.directory}?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ) ??
                false;
            if (yes) {
              widget.onDelete(widget.directory);
            } else {
              return;
            }
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
