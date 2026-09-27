import 'package:flutter/material.dart';

/// A network image with a device placeholder for loading, missing and broken images.
class ProductImage extends StatelessWidget {
  const ProductImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.iconSize = 40,
    this.semanticLabel,
    this.backgroundColor,
  });

  final String? url;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final double iconSize;
  final String? semanticLabel;

  /// Painted behind a loaded image, e.g. white behind a product photo shown
  /// with [BoxFit.contain] (many shop photos have transparent backgrounds).
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget placeholder(IconData icon, {Widget? overlay}) => ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Icon(icon, size: iconSize, color: scheme.outline),
          ),
          if (overlay != null) overlay,
        ],
      ),
    );

    final source = url;
    Widget child;
    if (source == null || source.isEmpty) {
      child = placeholder(Icons.devices);
    } else {
      child = Image.network(
        source,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        semanticLabel: semanticLabel,
        // loadingBuilder gets no progress before the first bytes arrive, so
        // also show the placeholder until a frame has actually been decoded.
        frameBuilder: (context, image, frame, wasSynchronouslyLoaded) {
          if (!wasSynchronouslyLoaded && frame == null) {
            return placeholder(
              Icons.devices,
              overlay: const Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(minHeight: 3),
              ),
            );
          }
          return backgroundColor == null
              ? image
              : ColoredBox(color: backgroundColor!, child: image);
        },
        loadingBuilder: (context, image, progress) {
          if (progress == null) return image;
          final total = progress.expectedTotalBytes;
          return placeholder(
            Icons.devices,
            overlay: Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(
                value: total == null
                    ? null
                    : progress.cumulativeBytesLoaded / total,
                minHeight: 3,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) =>
            placeholder(Icons.broken_image_outlined),
      );
    }

    return borderRadius == null
        ? child
        : ClipRRect(borderRadius: borderRadius!, child: child);
  }
}
