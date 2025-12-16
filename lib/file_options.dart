import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:s3_drive/components.dart';
import 'package:share_plus/share_plus.dart';
import 'package:s3_drive/services/models/remote_file.dart';

class FileOptions extends StatefulWidget {
  final File file;
  final RemoteFile remoteFile;
  final Future<String> Function(int) onCopyFileLink;
  final Function() onDelete;
  final Function() onSave;
  final Function()? onDownload;
  final XFile Function()? onShare;

  const FileOptions({
    super.key,
    required this.file,
    required this.remoteFile,
    required this.onSave,
    required this.onCopyFileLink,
    required this.onDelete,
    this.onDownload,
    this.onShare,
  });

  @override
  FileOptionsState createState() => FileOptionsState();
}

class FileOptionsState extends State<FileOptions> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text(
              'Options for ${widget.file}',
              style: Theme.of(context).textTheme.headlineSmall,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (widget.file.existsSync())
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text('Open'),
            onTap: () async {
              await OpenFile.open(widget.file.path);
            },
          ),
        if (!widget.file.existsSync())
          ListTile(
            leading: const Icon(Icons.download),
            title: Text('Download'),
            subtitle: widget.onDownload == null
                ? Text('Set sync options to enable downloading')
                : null,
            onTap: widget.onDownload == null
                ? null
                : () {
                    widget.onDownload!();
                    Navigator.of(context).pop();
                  },
          ),
        ListTile(
          leading: const Icon(Icons.save),
          title: Text('Save As...'),
          onTap: () async {
            widget.onSave();
            Navigator.of(context).pop();
          },
        ),
        ListTile(
          leading: const Icon(Icons.share),
          title: Text('Share File'),
          subtitle: widget.file.existsSync()
              ? null
              : Text('Please download file before sharing'),
          onTap: widget.onShare != null
              ? () {
                  SharePlus.instance.share(
                    ShareParams(
                      files: [widget.onShare!()],
                    ),
                  );
                  Navigator.of(context).pop();
                }
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.link),
          title: Text('Copy Link'),
          onTap: () async {
            await Clipboard.setData(ClipboardData(
                text: await widget
                    .onCopyFileLink(await expiryDialog(context) ?? 3600)));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('File link copied to clipboard')),
            );
            Navigator.of(context).pop();
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete),
          title: Text('Delete'),
          subtitle: Text('Delete from device as well as S3'),
          onTap: () async {
            bool yes = await showDialog<bool>(
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
              widget.onDelete();
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
