// Packs PNG images into one .ico (PNG entries, Windows Vista and later). Usage: dart tool/make_ico.dart out.ico a.png b.png ...
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  final images = [for (final path in args.skip(1)) File(path).readAsBytesSync()];
  final header = ByteData(6 + 16 * images.length)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, images.length, Endian.little);
  var offset = header.lengthInBytes;
  for (var i = 0; i < images.length; i++) {
    final png = ByteData.sublistView(images[i]);
    final width = png.getUint32(16), height = png.getUint32(20);
    final entry = 6 + 16 * i;
    header
      ..setUint8(entry, width >= 256 ? 0 : width)
      ..setUint8(entry + 1, height >= 256 ? 0 : height)
      ..setUint16(entry + 4, 1, Endian.little)
      ..setUint16(entry + 6, 32, Endian.little)
      ..setUint32(entry + 8, images[i].length, Endian.little)
      ..setUint32(entry + 12, offset, Endian.little);
    offset += images[i].length;
  }
  final out = BytesBuilder()..add(header.buffer.asUint8List());
  images.forEach(out.add);
  File(args.first).writeAsBytesSync(out.toBytes());
}
