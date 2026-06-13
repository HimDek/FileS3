import 'dart:math' as math;

import 'package:flutter/material.dart';

class CustomThumbScrollbar extends StatelessWidget {
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
    this.thickness = 8,
    this.minThumbLength = 48,
    this.maxThumbLength = double.infinity,
    this.padding = EdgeInsets.zero,
    this.thumbVisibility = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RawScrollbar(
          controller: controller,
          thumbVisibility: thumbVisibility,
          interactive: true,
          thickness: thickness,
          thumbColor: Colors.transparent,
          child: RepaintBoundary(child: child),
        ),

        if (thumbVisibility)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  if (!controller.hasClients) {
                    return const SizedBox.shrink();
                  }

                  final p = controller.position;

                  try {
                    if (p.maxScrollExtent <= 0) {
                      return const SizedBox.shrink();
                    }
                  } catch (e) {
                    return const SizedBox.shrink();
                  }

                  final viewport = p.viewportDimension - padding.vertical;

                  if (viewport <= 0) {
                    return const SizedBox.shrink();
                  }

                  final total = p.maxScrollExtent + p.viewportDimension;

                  double thumbHeight = viewport * viewport / total;

                  thumbHeight = math.max(minThumbLength, thumbHeight);
                  thumbHeight = math.min(maxThumbLength, thumbHeight);
                  thumbHeight = math.min(thumbHeight, viewport);

                  // Handle iOS overscroll
                  final pixels = p.pixels.clamp(0.0, p.maxScrollExtent);

                  final maxThumbOffset = viewport - thumbHeight;

                  final top = p.maxScrollExtent == 0
                      ? 0.0
                      : pixels / p.maxScrollExtent * maxThumbOffset;

                  return Padding(
                    padding: padding,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Transform.translate(
                        offset: Offset(0, top),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (popup != null) RepaintBoundary(child: popup!),
                            SizedBox(
                              width: thickness,
                              height: thumbHeight,
                              child: RepaintBoundary(child: thumb),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
