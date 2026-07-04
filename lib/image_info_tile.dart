import 'dart:convert';

import 'package:expressions/expressions.dart';
import 'package:flutter/material.dart';
import 'package:m3e_card_list/m3e_card_list.dart';
import 'package:files3/helpers.dart';

class ImageInfoTile extends StatefulWidget {
  final Map<String, dynamic> metadata;
  final String? remoteKey;

  const ImageInfoTile({super.key, required this.metadata, this.remoteKey});

  @override
  ImageInfoTileState createState() => ImageInfoTileState();
}

class ImageInfoTileState extends State<ImageInfoTile> {
  bool isExpanded = false;
  int width = 0;
  int height = 0;
  final evaluator = const ExpressionEvaluator();

  Future<void> _loadResolution() async {
    if (widget.remoteKey != null) {
      final res = jsonDecode(
        ConfigManager.getString('${widget.remoteKey}_resolution') ?? '{}',
      );
      width =
          res['width'] ??
          int.tryParse(widget.metadata['imagewidth'] ?? '0') ??
          0;
      height =
          res['height'] ??
          int.tryParse(widget.metadata['imagelength'] ?? '0') ??
          0;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _loadResolution();
  }

  @override
  void didUpdateWidget(covariant ImageInfoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata != widget.metadata ||
        oldWidget.remoteKey != widget.remoteKey) {
      _loadResolution();
    }
  }

  @override
  Widget build(BuildContext context) {
    return M3ECardColumn(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      outerRadius: 18,
      innerRadius: 4,
      gap: 3,
      color: Colors.transparent,
      children: [
        if (widget.metadata['make'] != null ||
            widget.metadata['model'] != null ||
            widget.metadata['lensmake'] != null ||
            widget.metadata['lensmodel'] != null)
          ListTile(
            visualDensity: VisualDensity.comfortable,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            leading: Icon(Icons.camera_alt_rounded),
            title: Text(
              '${widget.metadata['make'] ?? widget.metadata['lensmake']} '
              '${widget.metadata['model'] ?? widget.metadata['lensmodel']}',
            ),
            subtitle: (widget.metadata['original'] != null)
                ? Text(
                    timeToReadable(DateTime.parse(widget.metadata['original'])),
                  )
                : null,
          ),
        // TODO: Show readable location if GPS coordinates are available
        if (widget.metadata['gps-gpslatituderef'] != null &&
            widget.metadata['gps-gpslongituderef'] != null &&
            widget.metadata['gps-gpslatituderef'].isNotEmpty &&
            widget.metadata['gps-gpslongituderef'].isNotEmpty)
          ListTile(
            visualDensity: VisualDensity.comfortable,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            leading: Icon(Icons.location_on_rounded),
            title: Text(
              '${widget.metadata['gps-gpslatituderef']}, ${widget.metadata['gps-gpslongituderef']}',
            ),
          ),
        if (width > 0 && height > 0)
          ListTile(
            visualDensity: VisualDensity.comfortable,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            leading: Icon(Icons.camera_rounded),
            title: Row(
              spacing: 16,
              children: [
                Text('${width}x$height'),
                Text(
                  "${(width * height / (1024 * 1024)).toStringAsFixed(1)} MP",
                ),
              ],
            ),
            subtitle:
                (widget.metadata['focallengthin35mmfilm'] != null ||
                    widget.metadata['focallength'] != null ||
                    widget.metadata['fnumber'] != null ||
                    widget.metadata['exposuretime'] != null ||
                    widget.metadata['isospeedratings'] != null ||
                    widget.metadata['exposurebiasvalue'] != null)
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if ((widget.metadata['focallengthin35mmfilm'] ??
                              widget.metadata['focallength']) !=
                          null)
                        Text(
                          '${evaluator.eval(Expression.parse(widget.metadata['focallengthin35mmfilm'] ?? widget.metadata['focallength']!), {})} mm',
                        ),
                      if (widget.metadata['fnumber'] != null)
                        Text(
                          'f/${evaluator.eval(Expression.parse(widget.metadata['fnumber']!), {})}',
                        ),
                      if (widget.metadata['exposuretime'] != null)
                        Text(
                          '${evaluator.eval(Expression.parse(widget.metadata['exposuretime']!), {})} s',
                        ),
                      if (widget.metadata['isospeedratings'] != null)
                        Text('ISO ${widget.metadata['isospeedratings']}'),
                      if (widget.metadata['exposurebiasvalue'] != null)
                        Text('${widget.metadata['exposurebiasvalue']} EV'),
                    ],
                  )
                : null,
          ),
      ],
    );
  }
}
