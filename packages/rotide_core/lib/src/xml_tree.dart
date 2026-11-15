/// A small XML reader for the parts of an Office Open XML package: elements with attributes and text, no DTD. The
/// files Word writes are machine-generated and well-formed; text outside elements and processing instructions are
/// dropped.
final class XmlElement {
  XmlElement(this.name, this.attributes);

  /// Qualified name as written, `w:p`.
  final String name;
  final Map<String, String> attributes;
  final children = <Object>[];

  Iterable<XmlElement> get elements => children.whereType<XmlElement>();

  XmlElement? child(String name) {
    for (final element in elements) {
      if (element.name == name) return element;
    }
    return null;
  }

  Iterable<XmlElement> all(String name) => elements.where((element) => element.name == name);

  String? operator [](String attribute) => attributes[attribute];

  /// All text inside, in order.
  String get text {
    final out = StringBuffer();
    void walk(XmlElement element) {
      for (final child in element.children) {
        if (child is String) {
          out.write(child);
        } else if (child is XmlElement) {
          walk(child);
        }
      }
    }

    walk(this);
    return out.toString();
  }

  static final _tag = RegExp(r'<(/?)([A-Za-z_][\w.:-]*)((?:\s+[\w.:-]+\s*=\s*(?:"[^"]*"|' "'[^']*'" r'))*)\s*(/?)>');
  static final _attribute = RegExp(r'([\w.:-]+)\s*=\s*(?:"([^"]*)"|' "'([^']*)')");

  /// Parses a document and returns its root element.
  static XmlElement parse(String source) {
    final root = XmlElement('#document', const {});
    final stack = <XmlElement>[root];
    var position = 0;
    while (position < source.length) {
      final open = source.indexOf('<', position);
      if (open < 0) break;
      if (open > position && stack.length > 1) stack.last.children.add(decode(source.substring(position, open)));
      if (source.startsWith('<!--', open)) {
        final end = source.indexOf('-->', open + 4);
        position = end < 0 ? source.length : end + 3;
        continue;
      }
      if (source.startsWith('<![CDATA[', open)) {
        final end = source.indexOf(']]>', open + 9);
        stack.last.children.add(source.substring(open + 9, end < 0 ? source.length : end));
        position = end < 0 ? source.length : end + 3;
        continue;
      }
      if (source.startsWith('<?', open) || source.startsWith('<!', open)) {
        final end = source.indexOf('>', open);
        position = end < 0 ? source.length : end + 1;
        continue;
      }
      final match = _tag.matchAsPrefix(source, open);
      if (match == null) {
        // A stray "<" in text: keep it as text.
        stack.last.children.add('<');
        position = open + 1;
        continue;
      }
      position = match.end;
      final name = match.group(2)!;
      if (match.group(1)!.isNotEmpty) {
        // Close the element and anything left open inside it.
        final index = stack.lastIndexWhere((element) => element.name == name);
        if (index > 0) stack.removeRange(index, stack.length);
        continue;
      }
      final attributes = <String, String>{
        for (final attribute in _attribute.allMatches(match.group(3)!)) attribute.group(1)!: decode(attribute.group(2) ?? attribute.group(3) ?? ''),
      };
      final element = XmlElement(name, attributes);
      stack.last.children.add(element);
      if (match.group(4)!.isEmpty) stack.add(element);
    }
    return root;
  }

  static final _entity = RegExp(r'&(#x[0-9A-Fa-f]+|#\d+|amp|lt|gt|quot|apos);');

  static String decode(String text) {
    if (!text.contains('&')) return text;
    return text.replaceAllMapped(_entity, (match) {
      final name = match.group(1)!;
      switch (name) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final code = name.startsWith('#x') ? int.tryParse(name.substring(2), radix: 16) : int.tryParse(name.substring(1));
      return code == null || code > 0x10FFFF ? match.group(0)! : String.fromCharCode(code);
    });
  }
}
