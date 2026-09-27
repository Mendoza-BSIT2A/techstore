import 'package:flutter/material.dart';

import 'product_image.dart';

/// Opens a full-screen, zoomable photo. [action] is shown at the bottom when given.
Future<void> showPhotoViewer(
  BuildContext context,
  String url, {
  String? caption,
  Widget? action,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: ProductImage(
                    url,
                    fit: BoxFit.contain,
                    semanticLabel: caption,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton.filledTonal(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            if (caption != null || action != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (caption != null)
                      Text(
                        caption,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    if (action != null) ...[const SizedBox(height: 12), action],
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
