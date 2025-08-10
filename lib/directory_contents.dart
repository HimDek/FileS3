import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:s3_drive/services/job.dart';
import 'package:s3_drive/services/models/remote_file.dart';

class DirectoryContents extends StatefulWidget {
  final String directory;
  final List<Job> jobs;
  final Map<String, List<RemoteFile>> remoteFilesMap;
  final Function(String) onChangeDirectory;

  const DirectoryContents({
    super.key,
    required this.directory,
    required this.jobs,
    required this.remoteFilesMap,
    required this.onChangeDirectory,
  });

  @override
  DirectoryContentsState createState() => DirectoryContentsState();
}

class DirectoryContentsState extends State<DirectoryContents> {
  @override
  Widget build(BuildContext context) {
    String dir = '${widget.directory.split('/').first}/';
    return ListView(
      children:
          [
            (
              {'name': '..', 'size': 0, 'file': null},
              ListTile(
                title: Text('..'),
                onTap: () {
                  widget.onChangeDirectory(
                    Directory(widget.directory).parent.path,
                  );
                },
              ),
            ),

            for (final job in widget.jobs.where(
              (job) =>
                  job.remoteKey.startsWith(widget.directory) &&
                  '${File(job.remoteKey).parent.path}/' == widget.directory,
            ))
              (
                {
                  'name': job.remoteKey.split('/').last,
                  'size': job.bytes,
                  'file': job.localFile,
                  'job': job,
                },
                ListTile(
                  title: Text(job.remoteKey.split('/').last),
                  onTap: () {
                    //TODO: Handle tap on the job
                  },
                ),
              ),

            for (RemoteFile file in widget.remoteFilesMap[dir] ?? [])
              if (file.key.split('/').last.isNotEmpty &&
                  '${File(file.key).parent.path}/' == widget.directory)
                (
                  {
                    'name': file.key.split('/').last,
                    'size': file.size,
                    'file': file,
                  },
                  ListTile(
                    title: Text(file.key.split('/').last),
                    onTap: () {
                      //TODO: Handle tap on the remote file
                    },
                  ),
                ),
          ].map((item) {
            return item.$2;
          }).toList(),
    );
  }
}
