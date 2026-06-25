import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/models.dart';
import 'package:files3/helpers.dart';
import 'package:files3/media_view.dart';

class ExternalFiles extends StatefulWidget {
  final List<String> path;
  final Function(List<String>) upload;

  const ExternalFiles({super.key, required this.path, required this.upload});

  @override
  State<ExternalFiles> createState() => _ExternalFilesState();
}

class _ExternalFilesState extends State<ExternalFiles> {
  final RegExp _urlPattern = RegExp(r'^[a-zA-Z]+://');
  final List<GalleryProps> _files = [];
  final ManualNotifier _rebuildContextNotifier = ManualNotifier();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final GlobalKey<AnimatedGridState> _gridKey = GlobalKey<AnimatedGridState>();
  final ValueNotifier<double> _progress = ValueNotifier<double>(0.0);
  final ValueNotifier<ViewMode> _viewMode = ValueNotifier<ViewMode>(
    ViewMode.list,
  );
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;

  Future<void> _pushGallery(BuildContext context, int index) async {
    String? key = await Navigator.of(context).push(
      MaterialPageRoute<String>(
        builder: (context) => Gallery(
          files: _files,
          buildContextMenu: (context, index) {
            return ListenableBuilder(
              listenable: _rebuildContextNotifier,
              builder: (context, _) => Column(
                children:
                    _files[index].path != null &&
                        File(_files[index].path!).existsSync()
                    ? [
                        ListTile(
                          visualDensity: VisualDensity.comfortable,
                          leading: Icon(
                            mediaTypeIcon(getMediaType(_files[index].path!)),
                          ),
                          title: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(_files[index].path!),
                          ),
                          subtitle: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                Text(
                                  bytesToReadable(
                                    File(_files[index].path!).lengthSync(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(p.context.extension(_files[index].path!)),
                              ],
                            ),
                          ),
                        ),
                        ListTile(
                          visualDensity: VisualDensity.comfortable,
                          leading: const Icon(Icons.open_in_new),
                          title: const Text('Open with...'),
                          subtitle: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(_files[index].path!),
                          ),
                          onTap: () {
                            OpenFile.open(_files[index].path!);
                          },
                        ),
                        ListTile(
                          visualDensity: VisualDensity.comfortable,
                          leading: const Icon(Icons.share),
                          title: const Text('Share'),
                          onTap: () {
                            SharePlus.instance.share(
                              ShareParams(
                                files: <XFile>[XFile(_files[index].path!)],
                              ),
                            );
                          },
                        ),
                        ListTile(
                          visualDensity: VisualDensity.comfortable,
                          leading: const Icon(Icons.upload),
                          title: const Text('Upload'),
                          onTap: () => widget.upload([_files[index].path!]),
                        ),
                      ]
                    : [
                        ListTile(
                          visualDensity: VisualDensity.comfortable,
                          leading: const Icon(Icons.info_outline),
                          title: const Text('Loading...'),
                          subtitle: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              _files[index].path ??
                                  _files[index].url ??
                                  _files[index].key!,
                            ),
                          ),
                        ),
                      ],
              ),
            );
          },
          rebuildContext: () {
            _rebuildContextNotifier.notifyListeners();
          },
        ),
      ),
    );
    _scrollController.animateTo(
      64.0 * _files.indexWhere((file) => file.key == key),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
    });
    final int total = widget.path.length;
    int i = 0;
    for (final path in widget.path) {
      String normalizedPath = path;
      if (_urlPattern.hasMatch(path)) {
        normalizedPath = (await uriToFile(
          path,
          onProgress: (d, t) => _progress.value = (i + (d / t)) / total,
        )).path;
      }
      i++;
      _files.add(GalleryProps(key: path, path: normalizedPath));
      _listKey.currentState?.insertItem(_files.length - 1);
      _gridKey.currentState?.insertItem(_files.length - 1);
    }
    setState(() {
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Received Files'),
            Text(
              '${_files.length} file${_files.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (_files.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.upload),
              onPressed: () => widget.upload(
                _files
                    .map((file) => file.path ?? file.url ?? file.key!)
                    .toList(),
              ),
            ),
          IconButton(
            icon: Icon(
              _viewMode.value == ViewMode.grid ? Icons.list : Icons.grid_view,
            ),
            onPressed: () {
              _viewMode.value = _viewMode.value == ViewMode.grid
                  ? ViewMode.list
                  : ViewMode.grid;
              setState(() {});
            },
          ),
        ],
        bottom: _loading
            ? PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (context, value, child) =>
                      LinearProgressIndicator(value: value),
                ),
              )
            : null,
      ),
      body: _viewMode.value == ViewMode.list
          ? AnimatedList(
              key: _listKey,
              initialItemCount: _files.length,
              controller: _scrollController,
              itemBuilder: (context, index, animation) {
                return ListTile(
                  visualDensity: VisualDensity.compact,
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 16, right: 0),
                  leading: SizedBox(
                    width: 32,
                    height: 32,
                    child: Hero(
                      tag: _files[index].key!,
                      child: MediaPreview(
                        path: _files[index].path,
                        width: 256,
                        height: 256,
                      ),
                    ),
                  ),
                  title: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Text(
                      _files[index].path ?? _files[index].url ?? 'Unknown',
                    ),
                  ),
                  subtitle: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (_files[index].path != null &&
                            File(_files[index].path!).existsSync())
                          Text(
                            bytesToReadable(
                              File(_files[index].path!).lengthSync(),
                            ),
                          ),
                        if (_files[index].path != null &&
                            File(_files[index].path!).existsSync())
                          const SizedBox(width: 8),
                        if (_files[index].path != null &&
                            File(_files[index].path!).existsSync())
                          Text(p.context.extension(_files[index].path!)),
                      ],
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      final prop = _files[index];
                      _listKey.currentState?.removeItem(
                        index,
                        (context, animation) => SizeTransition(
                          sizeFactor: animation,
                          child: ListTile(
                            leading: Hero(
                              tag: prop.key!,
                              child: MediaPreview(
                                path: prop.path,
                                width: 32,
                                height: 32,
                              ),
                            ),
                          ),
                        ),
                        duration: const Duration(milliseconds: 300),
                      );
                      setState(() {});
                      _files.removeAt(index);
                      if (_files.isEmpty) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  onTap: () => _pushGallery(context, index),
                );
              },
            )
          : AnimatedGrid(
              key: _gridKey,
              initialItemCount: _files.length,
              controller: _scrollController,
              itemBuilder: (context, index, animation) {
                return GestureDetector(
                  onTap: () => _pushGallery(context, index),
                  child: GridTile(
                    header: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: GestureDetector(
                            child: const Icon(Icons.close),
                            onTap: () {
                              final prop = _files[index];
                              _gridKey.currentState?.removeItem(
                                index,
                                (context, animation) => SizeTransition(
                                  sizeFactor: animation,
                                  child: GridTile(
                                    child: Hero(
                                      tag: prop.key!,
                                      child: MediaPreview(
                                        path: prop.path,
                                        width: 256,
                                        height: 256,
                                      ),
                                    ),
                                  ),
                                ),
                                duration: const Duration(milliseconds: 300),
                              );
                              setState(() {});
                              _files.removeAt(index);
                              if (_files.isEmpty) {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    footer: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Text(
                          p.context.basename(
                            _files[index].path ??
                                _files[index].url ??
                                'Unknown',
                          ),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Hero(
                        tag: _files[index].key!,
                        child: MediaPreview(
                          path: _files[index].path,
                          width: 256,
                          height: 256,
                        ),
                      ),
                    ),
                  ),
                );
              },
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width < 600 ? 4 : 6,
                childAspectRatio: 3 / 4,
              ),
            ),
    );
  }
}
