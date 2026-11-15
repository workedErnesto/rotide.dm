import 'dart:convert';
import 'dart:typed_data';

/// A ZIP archive with stored (uncompressed) entries: enough for an Office Open XML package, which Word, Pages and
/// LibreOffice accept with or without compression.
final class ZipArchive {
  final _data = BytesBuilder(copy: false);
  final _directory = BytesBuilder(copy: false);
  var _count = 0;

  void addText(String path, String text) => add(path, utf8.encode(text));

  void add(String path, List<int> content) {
    final name = utf8.encode(path);
    final crc = Crc32.checksum(content);
    final offset = _data.length;
    // Local file header; time and date 1980-01-01.
    _data
      ..add(_le32(0x04034b50))
      ..add(_le16(20))
      ..add(_le16(0x0800))
      ..add(_le16(0))
      ..add(_le16(0))
      ..add(_le16(0x21))
      ..add(_le32(crc))
      ..add(_le32(content.length))
      ..add(_le32(content.length))
      ..add(_le16(name.length))
      ..add(_le16(0))
      ..add(name)
      ..add(content);
    // Central directory entry.
    _directory
      ..add(_le32(0x02014b50))
      ..add(_le16(20))
      ..add(_le16(20))
      ..add(_le16(0x0800))
      ..add(_le16(0))
      ..add(_le16(0))
      ..add(_le16(0x21))
      ..add(_le32(crc))
      ..add(_le32(content.length))
      ..add(_le32(content.length))
      ..add(_le16(name.length))
      ..add(_le16(0))
      ..add(_le16(0))
      ..add(_le16(0))
      ..add(_le16(0))
      ..add(_le32(0))
      ..add(_le32(offset))
      ..add(name);
    _count += 1;
  }

  Uint8List finish() {
    final directory = _directory.toBytes();
    final start = _data.length;
    final result = BytesBuilder(copy: false)
      ..add(_data.toBytes())
      ..add(directory)
      ..add(_le32(0x06054b50))
      ..add(_le16(0))
      ..add(_le16(0))
      ..add(_le16(_count))
      ..add(_le16(_count))
      ..add(_le32(directory.length))
      ..add(_le32(start))
      ..add(_le16(0));
    return result.toBytes();
  }

  static Uint8List _le16(int value) => Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
  static Uint8List _le32(int value) => Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
}

abstract final class Crc32 {
  static final _table = List<int>.generate(256, (index) {
    var c = index;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int checksum(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}
