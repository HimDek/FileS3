import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'package:path/path.dart' as p;

class FileOptions extends StatefulWidget {
  final File file;
  final RemoteFile remoteFile;
  final Function(String) onDelete;

  const FileOptions({
    super.key,
    required this.file,
    required this.remoteFile,
    required this.onDelete,
  });

  @override
  FileOptionsState createState() => FileOptionsState();
}

class FileOptionsState extends State<FileOptions> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Center(
          child: Text(
            'Options for ${widget.file}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 24),
        ListTile(
          leading: const Icon(Icons.open_in_new),
          title: Text('Open'),
          onTap: () async {
            await OpenFile.open(widget.file.path);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete),
          title: Text('Delete'),
          subtitle: Text('Delete from device as well as S3'),
          onTap: () async {
            bool yes =
                await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete File'),
                    content: Text(
                      'Are you sure you want to delete ${widget.file.path} from your device and S3? This action cannot be undone.',
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
              widget.onDelete(widget.remoteFile.key);
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
