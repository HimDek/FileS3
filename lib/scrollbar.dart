import 'dart:math' as math;
import 'package:flutter/material.dart';

class CustomThumbScrollbar extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  final Widget thumb;
  final Widget? popup;

  final double thickness;
  final double minThumbLength;
  final double maxThumbLength;
  final EdgeInsets padding;
  final bool thumbVisibility;

  const CustomThumbScrollbar({
    super.key,
    required this.controller,
    required this.child,
    required this.thumb,
    this.popup,
    this.thickness = 6,
    this.minThumbLength = 16,
    this.maxThumbLength = double.infinity,
    this.padding = EdgeInsets.zero,
    this.thumbVisibility = true,
  });

  @override
  State<CustomThumbScrollbar> createState() => _CustomThumbScrollbarState();
}

class _CustomThumbScrollbarState extends State<CustomThumbScrollbar> {
  final GlobalKey _trackKey = GlobalKey();
  final ValueNotifier<bool> _popupVisible = ValueNotifier(false);
  double _grabOffset = 0;

  void _showPopup() {
    if (widget.popup == null) return;

    _popupVisible.value = true;
  }

  void _hidePopup() {
    _popupVisible.value = false;
  }

  @override
  void didUpdateWidget(covariant CustomThumbScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);

    _popupVisible.value = widget.thumbVisibility ? _popupVisible.value : false;
  }

  @override
  void dispose() {
    _popupVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RawScrollbar(
          controller: widget.controller,
          thumbVisibility: widget.thumbVisibility,
          interactive: false,
          thickness: widget.thickness,
          thumbColor: Colors.transparent,
          child: RepaintBoundary(child: widget.child),
        ),

        Positioned.fill(
          key: _trackKey,
          child: Padding(
            padding: widget.padding,
            child: Align(
              alignment: Alignment.topRight,
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  if (!widget.controller.hasClients) {
                    return const SizedBox.shrink();
                  }

                  final p = widget.controller.position;

                  if (p.maxScrollExtent <= 0) {
                    return const SizedBox.shrink();
                  }

                  final viewport =
                      p.viewportDimension - widget.padding.vertical;

                  if (viewport <= 0) {
                    return const SizedBox.shrink();
                  }

                  final total = p.maxScrollExtent + p.viewportDimension;

                  double thumbHeight = viewport * viewport / total;

                  thumbHeight =
                      MediaQuery.paddingOf(context).top +
                      thumbHeight.clamp(
                        widget.minThumbLength,
                        widget.maxThumbLength,
                      ) +
                      MediaQuery.paddingOf(context).bottom;

                  thumbHeight = math.min(thumbHeight, viewport);

                  final pixels = p.pixels.clamp(0.0, p.maxScrollExtent);

                  final maxThumbOffset = viewport - thumbHeight;

                  final top = maxThumbOffset <= 0
                      ? 0.0
                      : pixels / p.maxScrollExtent * maxThumbOffset;

                  return Transform.translate(
                    offset: Offset(0, top),
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          padding: EdgeInsets.only(
                            top: MediaQuery.paddingOf(context).top,
                            bottom: MediaQuery.paddingOf(context).bottom,
                          ),
                          height: thumbHeight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.popup != null)
                                RepaintBoundary(
                                  child: ListenableBuilder(
                                    listenable: _popupVisible,
                                    builder: (context, _) {
                                      return Transform.translate(
                                        offset: Offset(
                                          0,
                                          -(thumbHeight -
                                                  MediaQuery.paddingOf(
                                                    context,
                                                  ).top -
                                                  MediaQuery.paddingOf(
                                                    context,
                                                  ).bottom) /
                                              2,
                                        ),
                                        child: AnimatedScale(
                                          scale: _popupVisible.value ? 1 : 0,
                                          alignment: Alignment.centerRight,
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                          child: RepaintBoundary(
                                            child: widget.popup!,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              AnimatedScale(
                                scale: widget.thumbVisibility ? 1 : 0,
                                duration: const Duration(milliseconds: 150),
                                child: SizedBox(
                                  width: widget.thickness,
                                  child: RepaintBoundary(child: widget.thumb),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.thumbVisibility)
                          RepaintBoundary(
                            child: SizedBox(
                              width: math.max(widget.thickness, 48),
                              height:
                                  thumbHeight +
                                  math.max(
                                    MediaQuery.paddingOf(context).top,
                                    MediaQuery.paddingOf(context).bottom,
                                  ),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,

                                onTapDown: (_) => _showPopup(),

                                onTapCancel: _hidePopup,

                                onVerticalDragDown: (_) => _showPopup(),

                                onVerticalDragStart: (details) {
                                  _grabOffset = details.localPosition.dy;

                                  _showPopup();
                                },

                                onVerticalDragCancel: _hidePopup,

                                onVerticalDragEnd: (_) => _hidePopup(),

                                onVerticalDragUpdate: (details) {
                                  final context = _trackKey.currentContext;

                                  if (context == null) {
                                    return;
                                  }

                                  final box =
                                      context.findRenderObject() as RenderBox;

                                  final local = box.globalToLocal(
                                    details.globalPosition,
                                  );

                                  final newTop =
                                      (local.dy -
                                              widget.padding.top -
                                              _grabOffset)
                                          .clamp(0.0, maxThumbOffset);

                                  if (maxThumbOffset <= 0) {
                                    return;
                                  }

                                  final scrollOffset =
                                      (newTop /
                                              maxThumbOffset *
                                              p.maxScrollExtent)
                                          .clamp(0.0, p.maxScrollExtent);

                                  widget.controller.jumpTo(scrollOffset);
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
