import 'dart:typed_data';

/// Pixel size and density of a PNG, JPEG or GIF read from its header, for embedding images at their own size.
final class ImageInfo {
  const ImageInfo(this.width, this.height, this.dpi);
  final int width;
  final int height;

  /// Horizontal density; 72 when the file does not say.
  final double dpi;

  static ImageInfo? read(Uint8List bytes) {
    if (bytes.length < 24) return null;
    final data = ByteData.sublistView(bytes);
    // PNG: IHDR carries the size; pHYs (pixels per metre) the density.
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      final width = data.getUint32(16), height = data.getUint32(20);
      var dpi = 72.0;
      var offset = 8;
      while (offset + 12 <= bytes.length) {
        final length = data.getUint32(offset);
        final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
        if (type == 'pHYs' && offset + 17 <= bytes.length && bytes[offset + 16] == 1) {
          final perMetre = data.getUint32(offset + 8);
          if (perMetre > 0) dpi = perMetre * 0.0254;
          break;
        }
        if (type == 'IDAT' || type == 'IEND') break;
        offset += 12 + length;
      }
      return ImageInfo(width, height, dpi);
    }
    // GIF: logical screen size, little endian.
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return ImageInfo(data.getUint16(6, Endian.little), data.getUint16(8, Endian.little), 72);
    }
    // JPEG: JFIF density in APP0, size in the first start-of-frame marker.
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      var dpi = 72.0;
      var offset = 2;
      while (offset + 4 <= bytes.length) {
        if (bytes[offset] != 0xFF) {
          offset += 1;
          continue;
        }
        final marker = bytes[offset + 1];
        if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
          offset += 2;
          continue;
        }
        final length = data.getUint16(offset + 2);
        if (marker == 0xE0 && offset + 16 <= bytes.length && String.fromCharCodes(bytes, offset + 4, offset + 8) == 'JFIF') {
          final units = bytes[offset + 11];
          final x = data.getUint16(offset + 12);
          if (x > 0 && units == 1) dpi = x.toDouble();
          if (x > 0 && units == 2) dpi = x * 2.54;
        }
        final frame = (marker >= 0xC0 && marker <= 0xCF) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
        if (frame && offset + 9 <= bytes.length) {
          return ImageInfo(data.getUint16(offset + 7), data.getUint16(offset + 5), dpi);
        }
        offset += 2 + length;
      }
    }
    return null;
  }
}
