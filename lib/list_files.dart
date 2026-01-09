import 'dart:io';
import 'package:flutter/material.dart';
import 'package:enough_media/enough_media.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/gallery.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';
import 'package:files3/jobs.dart';

class MyGridTile extends StatelessWidget {
  final Widget child;
  final Widget? footer;
  final bool selected;
  final Widget? topLeftBadge;
  final Widget? topRightBadge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MyGridTile({
    super.key,
    required this.child,
    this.footer,
    this.selected = false,
    this.topLeftBadge,
    this.topRightBadge,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
        ),
        child: GridTile(
          header: topRightBadge != null || topLeftBadge != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    topLeftBadge ?? SizedBox.shrink(),
                    topRightBadge ?? SizedBox.shrink(),
                  ],
                )
              : null,
          footer: AnimatedContainer(
            duration: Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surface,
            ),
            padding: EdgeInsets.all(8),
            child: footer,
          ),
          child: AnimatedPadding(
            duration: Duration(milliseconds: 100),
            padding: EdgeInsets.only(
              left: selected ? 8 : 0,
              right: selected ? 8 : 0,
              top: selected ? 8 : 0,
              bottom: selected ? 40 : 32,
            ),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 100),
              decoration: BoxDecoration(
                border: selected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : null,
                borderRadius: BorderRadius.circular(4),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class ListFiles extends StatelessWidget {
  final List<dynamic> files;
  final SortMode sortMode;
  final bool foldersFirst;
  final bool gridView;
  final RemoteFile relativeto;
  final Set<RemoteFile> selection;
  final SelectionAction selectionAction;
  final Function() onUpdate;
  final Function()? Function(RemoteFile) changeDirectory;
  final Function(RemoteFile) select;
  final Function(RemoteFile) showContextMenu;
  final (int, int) Function(RemoteFile, {bool recursive}) count;
  final int Function(RemoteFile) dirSize;
  final String Function(RemoteFile) dirModified;
  final String? Function(RemoteFile, int?) getLink;

  const ListFiles({
    super.key,
    required this.files,
    required this.sortMode,
    required this.foldersFirst,
    required this.gridView,
    required this.relativeto,
    required this.selection,
    required this.selectionAction,
    required this.onUpdate,
    required this.changeDirectory,
    required this.select,
    required this.showContextMenu,
    required this.count,
    required this.dirSize,
    required this.dirModified,
    required this.getLink,
  });

  Widget listItemBuilder(BuildContext context, FileProps item) {
    return item.job != null
        ? JobView(job: item.job!, relativeTo: relativeto, onUpdate: onUpdate)
        : item.key.endsWith('/')
        ? ListTile(
            dense: MediaQuery.of(context).size.width < 600 ? true : false,
            visualDensity: MediaQuery.of(context).size.width < 600
                ? VisualDensity.compact
                : VisualDensity.standard,
            selected: selection.any((selected) {
              return selected.key == item.key;
            }),
            selectedTileColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.1),
            selectedColor: Theme.of(context).colorScheme.primary,
            leading: Icon(
              p.split(item.key).length > 1
                  ? Icons.folder
                  : Icons.cloud_circle_rounded,
            ),
            title: Text(
              p.isWithin(relativeto.key, item.key)
                  ? "${p.relative(item.key, from: relativeto.key)}/"
                  : "${item.key}/",
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(dirModified(item.file!)),
                      SizedBox(width: 8),
                      Text(bytesToReadable(dirSize(item.file!))),
                      SizedBox(width: 8),
                      Text(() {
                        final count = this.count(item.file!, recursive: true);
                        if (count.$1 == 0) {
                          return '${count.$2} files';
                        }
                        if (count.$2 == 0) {
                          return '${count.$1} subfolders';
                        }
                        return '${count.$2} files in ${count.$1} subfolders';
                      }()),
                    ],
                  ),
                ),
                if (p.dirname(item.file!.key).isEmpty)
                  Row(
                    children: [
                      Text('${Main.backupMode(item.file!.key).name}:'),
                      SizedBox(width: 4),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          Main.pathFromKey(item.file!.key) ?? 'Not set',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            onTap:
                selection.isNotEmpty && selectionAction == SelectionAction.none
                ? () {
                    select(item.file!);
                  }
                : selection.any(
                    (s) => p.isWithin(s.key, item.key) || s.key == item.key,
                  )
                ? null
                : changeDirectory(item.file!),
            onLongPress: selectionAction == SelectionAction.none
                ? () {
                    select(item.file!);
                  }
                : null,
            trailing: selection.isNotEmpty
                ? selection.isEmpty ||
                          selection.any((selected) {
                            return selected.key == item.key;
                          })
                      ? Icon(Icons.check)
                      : null
                : IconButton(
                    onPressed: () async {
                      showContextMenu(item.file!);
                    },
                    icon: Icon(Icons.more_vert),
                  ),
          )
        : ListTile(
            dense: MediaQuery.of(context).size.width < 600 ? true : false,
            visualDensity: MediaQuery.of(context).size.width < 600
                ? VisualDensity.compact
                : VisualDensity.standard,
            selected: selection.any((selected) {
              return selected.key == item.key;
            }),
            selectedTileColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.1),
            selectedColor: Theme.of(context).colorScheme.primary,
            leading: getMediaType(item.key) != null
                ? SizedBox(
                    height: 24,
                    width: 24,
                    child: PreviewMediaWidget(
                      height: 24,
                      width: 24,
                      mediaProvider: getMediaProvider(
                        name: p.isWithin(relativeto.key, item.key)
                            ? p.relative(item.key, from: relativeto.key)
                            : item.file!.key,
                        mediaType: getMediaType(item.key)!,
                        url: item.url!,
                        path:
                            File(
                              Main.pathFromKey(item.key) ?? item.key,
                            ).existsSync()
                            ? (Main.pathFromKey(item.key) ?? item.key)
                            : Main.cachePathFromKey(item.key),
                        size: item.size,
                      ),
                      fallbackBuilder: (_, media) => Icon(
                        media.isImage
                            ? Icons.image
                            : media.isVideo
                            ? Icons.videocam
                            : media.isAudio
                            ? Icons.audiotrack
                            : media.isText
                            ? Icons.description
                            : media.isFont
                            ? Icons.font_download
                            : media.isMessage
                            ? Icons.message
                            : media.isModel
                            ? Icons.model_training
                            : media.isApplication
                            ? media.mediaType.toLowerCase() == 'application/pdf'
                                  ? Icons.picture_as_pdf
                                  : Icons.apps
                            : Icons.insert_drive_file,
                      ),
                    ),
                  )
                : Icon(Icons.insert_drive_file),
            title: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                p.isWithin(relativeto.key, item.key)
                    ? p.relative(item.key, from: relativeto.key)
                    : item.file!.key,
              ),
            ),
            subtitle: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(timeToReadable(item.file!.lastModified!)),
                  SizedBox(width: 8),
                  Text(bytesToReadable(item.size)),
                  SizedBox(width: 8),
                  File(Main.pathFromKey(item.key) ?? item.key).existsSync()
                      ? Icon(Icons.download_done, size: 16)
                      : Icon(
                          Icons.cloud_download,
                          color: Theme.of(context).colorScheme.primary,
                          size: 16,
                        ),
                  SizedBox(width: 8),
                  Text(
                    item.key.split('.').length > 1
                        ? '.${item.key.split('.').last}'
                        : '',
                  ),
                ],
              ),
            ),
            trailing: selection.isNotEmpty
                ? selection.any((selected) {
                        return selected.key == item.key;
                      })
                      ? Icon(Icons.check)
                      : null
                : IconButton(
                    onPressed: () async {
                      showContextMenu(item.file!);
                    },
                    icon: Icon(Icons.more_vert),
                  ),
            onTap:
                selection.isNotEmpty && selectionAction == SelectionAction.none
                ? () {
                    select(item.file!);
                  }
                : selectionAction != SelectionAction.none
                ? null
                : () {
                    final galleryFiles = files
                        .where((f) {
                          return !f.key.endsWith('/');
                        })
                        .map((f) {
                          String url =
                              getLink(
                                f is Job
                                    ? RemoteFile(
                                        key: f.remoteKey,
                                        size: f.bytes,
                                        etag: f.md5.toString(),
                                      )
                                    : f,
                                null,
                              ) ??
                              '';
                          return GalleryProps(
                            title: p.isWithin(relativeto.key, f.key)
                                ? p.relative(f.key, from: relativeto.key)
                                : f.key,
                            key: f.key,
                            url: url,
                            path:
                                File(
                                  Main.pathFromKey(f.key) ?? f.key,
                                ).existsSync()
                                ? (Main.pathFromKey(f.key) ?? f.key)
                                : Main.cachePathFromKey(f.key),
                            size: f.size,
                          );
                        })
                        .toList();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => Gallery(
                          files: galleryFiles,
                          initialIndex: galleryFiles.indexWhere(
                            (f) => f.key == item.key,
                          ),
                        ),
                      ),
                    );
                  },
            onLongPress: selectionAction == SelectionAction.none
                ? () {
                    select(item.file!);
                  }
                : null,
          );
  }

  Widget gridItemBuilder(BuildContext context, FileProps item) {
    return item.job != null
        ? SizedBox(height: 100, width: 100)
        : item.key.endsWith('/')
        ? MyGridTile(
            selected: selection.any((selected) {
              return selected.key == item.key;
            }),
            footer: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    p.isWithin(relativeto.key, item.key)
                        ? "${p.relative(item.key, from: relativeto.key)}/"
                        : "${item.key}/",
                  ),
                ),
                if (p.dirname(item.file!.key).isEmpty)
                  Row(
                    children: [
                      Text('${Main.backupMode(item.file!.key).name}:'),
                      SizedBox(width: 4),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          Main.pathFromKey(item.file!.key) ?? 'Not set',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            onTap:
                selection.isNotEmpty && selectionAction == SelectionAction.none
                ? null
                : selection.any(
                    (s) => p.isWithin(s.key, item.key) || s.key == item.key,
                  )
                ? null
                : changeDirectory(item.file!),
            onLongPress: selectionAction == SelectionAction.none
                ? () {
                    select(item.file!);
                  }
                : null,
            topRightBadge: selection.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      selection.isEmpty ||
                              selection.any((selected) {
                                return selected.key == item.key;
                              })
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: selectionAction == SelectionAction.none
                        ? () {
                            select(item.file!);
                          }
                        : null,
                  )
                : IconButton(
                    onPressed: () async {
                      showContextMenu(item.file!);
                    },
                    icon: Icon(Icons.more_vert),
                  ),
            child: Icon(
              p.split(item.key).length > 1
                  ? Icons.folder
                  : Icons.cloud_circle_rounded,
            ),
          )
        : MyGridTile(
            selected: selection.any((selected) {
              return selected.key == item.key;
            }),
            footer: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    p.isWithin(relativeto.key, item.key)
                        ? p.relative(item.key, from: relativeto.key)
                        : item.file!.key,
                  ),
                ),
              ],
            ),
            topLeftBadge: Padding(
              padding: EdgeInsets.all(16),
              child: File(Main.pathFromKey(item.key) ?? item.key).existsSync()
                  ? Icon(Icons.download_done, size: 16)
                  : Icon(
                      Icons.cloud_download,
                      color: Theme.of(context).colorScheme.primary,
                      size: 16,
                    ),
            ),
            topRightBadge: selection.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      selection.any((selected) {
                            return selected.key == item.key;
                          })
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: selectionAction == SelectionAction.none
                        ? () {
                            select(item.file!);
                          }
                        : null,
                  )
                : IconButton(
                    onPressed: () async {
                      showContextMenu(item.file!);
                    },
                    icon: Icon(Icons.more_vert),
                  ),
            onTap: () {
              final galleryFiles = files
                  .where((f) {
                    return !f.key.endsWith('/');
                  })
                  .map((f) {
                    String url =
                        getLink(
                          f is Job
                              ? RemoteFile(
                                  key: f.remoteKey,
                                  size: f.bytes,
                                  etag: f.md5.toString(),
                                )
                              : f,
                          null,
                        ) ??
                        '';
                    return GalleryProps(
                      title: p.isWithin(relativeto.key, f.key)
                          ? p.relative(f.key, from: relativeto.key)
                          : f.key,
                      key: f.key,
                      url: url,
                      path: File(Main.pathFromKey(f.key) ?? f.key).existsSync()
                          ? (Main.pathFromKey(f.key) ?? f.key)
                          : Main.cachePathFromKey(f.key),
                      size: f.size,
                    );
                  })
                  .toList();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => Gallery(
                    files: galleryFiles,
                    initialIndex: galleryFiles.indexWhere(
                      (f) => f.key == item.key,
                    ),
                  ),
                ),
              );
            },
            onLongPress: selectionAction == SelectionAction.none
                ? () {
                    select(item.file!);
                  }
                : null,
            child: getMediaType(item.key) != null
                ? SizedBox(
                    height: 24,
                    width: 24,
                    child: PreviewMediaWidget(
                      height: 24,
                      width: 24,
                      mediaProvider: getMediaProvider(
                        name: p.isWithin(relativeto.key, item.key)
                            ? p.relative(item.key, from: relativeto.key)
                            : item.file!.key,
                        mediaType: getMediaType(item.key)!,
                        url: item.url!,
                        path:
                            File(
                              Main.pathFromKey(item.key) ?? item.key,
                            ).existsSync()
                            ? (Main.pathFromKey(item.key) ?? item.key)
                            : Main.cachePathFromKey(item.key),
                        size: item.size,
                      ),
                      fallbackBuilder: (_, media) => Icon(
                        media.isImage
                            ? Icons.image
                            : media.isVideo
                            ? Icons.videocam
                            : media.isAudio
                            ? Icons.audiotrack
                            : media.isText
                            ? Icons.description
                            : media.isFont
                            ? Icons.font_download
                            : media.isMessage
                            ? Icons.message
                            : media.isModel
                            ? Icons.model_training
                            : media.isApplication
                            ? media.mediaType.toLowerCase() == 'application/pdf'
                                  ? Icons.picture_as_pdf
                                  : Icons.apps
                            : Icons.insert_drive_file,
                      ),
                    ),
                  )
                : Icon(Icons.insert_drive_file),
          );
  }

  @override
  Widget build(BuildContext context) {
    final sortedFiles = sort(
      files.map((file) {
        String url =
            getLink(
              file is Job
                  ? RemoteFile(
                      key: file.remoteKey,
                      size: file.bytes,
                      etag: file.md5.toString(),
                    )
                  : file,
              null,
            ) ??
            '';
        return file is Job
            ? FileProps(
                key: file.remoteKey,
                size: file.bytes,
                job: file,
                url: url,
              )
            : file.key.endsWith('/')
            ? FileProps(key: file.key, size: file.size, file: file, url: url)
            : FileProps(key: file.key, size: file.size, file: file, url: url);
      }),
      sortMode,
      foldersFirst,
    );
    return gridView
        ? SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width < 600 ? 4 : 6,
              childAspectRatio: 3 / 4,
            ),
            itemCount: sortedFiles.length,
            itemBuilder: (context, index) =>
                gridItemBuilder(context, sortedFiles[index]),
          )
        : SliverList.builder(
            itemCount: sortedFiles.length,
            itemBuilder: (context, index) =>
                listItemBuilder(context, sortedFiles[index]),
          );
  }
}
