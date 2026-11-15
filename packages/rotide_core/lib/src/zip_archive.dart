import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

/// Writes a ZIP archive with stored (uncompressed) entries: enough for an Office Open XML package, which Word, Pages and
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

/// Reads the entries of a ZIP archive, stored or deflated: what Word, Pages and LibreOffice write into a .docx.
final class ZipReader {
  ZipReader(this._bytes) : _view = ByteData.sublistView(_bytes) {
    _readDirectory();
  }

  final Uint8List _bytes;
  final ByteData _view;
  final _entries = <String, ({int method, int size, int offset})>{};

  Iterable<String> get names => _entries.keys;

  void _readDirectory() {
    // The end record is the last 22 bytes plus a comment of at most 64 KB.
    var end = -1;
    final lowest = _bytes.length - 22 - 0xFFFF < 0 ? 0 : _bytes.length - 22 - 0xFFFF;
    for (var i = _bytes.length - 22; i >= lowest; i--) {
      if (_view.getUint32(i, Endian.little) == 0x06054b50) {
        end = i;
        break;
      }
    }
    if (end < 0) throw const FormatException('файл не является архивом ZIP');
    final count = _view.getUint16(end + 10, Endian.little);
    var position = _view.getUint32(end + 16, Endian.little);
    for (var index = 0; index < count; index++) {
      if (position + 46 > _bytes.length || _view.getUint32(position, Endian.little) != 0x02014b50) {
        throw const FormatException('оглавление архива ZIP повреждено');
      }
      final method = _view.getUint16(position + 10, Endian.little);
      final size = _view.getUint32(position + 20, Endian.little);
      final nameLength = _view.getUint16(position + 28, Endian.little);
      final extraLength = _view.getUint16(position + 30, Endian.little);
      final commentLength = _view.getUint16(position + 32, Endian.little);
      final offset = _view.getUint32(position + 42, Endian.little);
      final name = utf8.decode(_bytes.sublist(position + 46, position + 46 + nameLength), allowMalformed: true);
      _entries[name] = (method: method, size: size, offset: offset);
      position += 46 + nameLength + extraLength + commentLength;
    }
  }

  /// The bytes of an entry, or null when the archive has no such entry.
  Uint8List? read(String name) {
    final entry = _entries[name];
    if (entry == null) return null;
    final header = entry.offset;
    if (header + 30 > _bytes.length || _view.getUint32(header, Endian.little) != 0x04034b50) {
      throw FormatException('запись «$name» архива ZIP повреждена');
    }
    final start = header + 30 + _view.getUint16(header + 26, Endian.little) + _view.getUint16(header + 28, Endian.little);
    final data = Uint8List.sublistView(_bytes, start, (start + entry.size).clamp(start, _bytes.length));
    return switch (entry.method) {
      0 => data,
      8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(data)),
      _ => throw FormatException('запись «$name» сжата неподдерживаемым способом'),
    };
  }

  String? text(String name) {
    final data = read(name);
    return data == null ? null : utf8.decode(data, allowMalformed: true);
  }
}
