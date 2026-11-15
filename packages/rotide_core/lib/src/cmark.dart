// FFI bindings to the vendored cmark-gfm, built by hook/build.dart into the native asset of this library.
// Only the calls rotide.dm uses; names follow the C API so the code reads like the Swift version it replaced.
import 'dart:convert';
import 'dart:ffi';

typedef NodePtr = Pointer<Void>;
typedef ParserPtr = Pointer<Void>;

/// Node types from cmark-gfm.h.
abstract final class NodeType {
  static const _block = 0x8000;
  static const _inline = 0xC000; // CMARK_NODE_TYPE_PRESENT | 0x4000
  static const document = _block | 0x0001;
  static const blockQuote = _block | 0x0002;
  static const list = _block | 0x0003;
  static const item = _block | 0x0004;
  static const codeBlock = _block | 0x0005;
  static const htmlBlock = _block | 0x0006;
  static const paragraph = _block | 0x0008;
  static const heading = _block | 0x0009;
  static const thematicBreak = _block | 0x000a;
  static const footnoteDefinition = _block | 0x000b;
  static const text = _inline | 0x0001;
  static const softBreak = _inline | 0x0002;
  static const lineBreak = _inline | 0x0003;
  static const code = _inline | 0x0004;
  static const htmlInline = _inline | 0x0005;
  static const emph = _inline | 0x0007;
  static const strong = _inline | 0x0008;
  static const link = _inline | 0x0009;
  static const image = _inline | 0x000a;
  static const footnoteReference = _inline | 0x000b;
}

abstract final class CmarkOption {
  static const unsafe = 1 << 17;
  static const footnotes = 1 << 13;
  static const githubPreLang = 1 << 11;
}

const _eventDone = 1;
const _eventEnter = 2;
const _orderedList = 2;

@Native<Void Function()>(symbol: 'cmark_gfm_core_extensions_ensure_registered')
external void _ensureRegistered();
@Native<ParserPtr Function(Int)>(symbol: 'cmark_parser_new')
external ParserPtr _parserNew(int options);
@Native<Void Function(ParserPtr)>(symbol: 'cmark_parser_free')
external void _parserFree(ParserPtr parser);
@Native<Pointer<Void> Function(Pointer<Char>)>(symbol: 'cmark_find_syntax_extension')
external Pointer<Void> _findExtension(Pointer<Char> name);
@Native<Int Function(ParserPtr, Pointer<Void>)>(symbol: 'cmark_parser_attach_syntax_extension')
external int _attachExtension(ParserPtr parser, Pointer<Void> extension);
@Native<Void Function(ParserPtr, Pointer<Char>, Size)>(symbol: 'cmark_parser_feed')
external void _parserFeed(ParserPtr parser, Pointer<Char> buffer, int length);
@Native<NodePtr Function(ParserPtr)>(symbol: 'cmark_parser_finish')
external NodePtr _parserFinish(ParserPtr parser);
@Native<Pointer<Void> Function(ParserPtr)>(symbol: 'cmark_parser_get_syntax_extensions')
external Pointer<Void> _parserExtensions(ParserPtr parser);
@Native<Pointer<Char> Function(NodePtr, Int, Pointer<Void>)>(symbol: 'cmark_render_html')
external Pointer<Char> _renderHtml(NodePtr root, int options, Pointer<Void> extensions);
@Native<Pointer<Char> Function(NodePtr, Int, Int)>(symbol: 'cmark_render_plaintext')
external Pointer<Char> _renderPlaintext(NodePtr root, int options, int width);
@Native<Pointer<_Mem> Function()>(symbol: 'cmark_get_default_mem_allocator')
external Pointer<_Mem> _allocator();

@Native<Pointer<Void> Function(NodePtr)>(symbol: 'cmark_iter_new')
external Pointer<Void> _iterNew(NodePtr root);
@Native<Int Function(Pointer<Void>)>(symbol: 'cmark_iter_next')
external int _iterNext(Pointer<Void> iterator);
@Native<NodePtr Function(Pointer<Void>)>(symbol: 'cmark_iter_get_node')
external NodePtr _iterNode(Pointer<Void> iterator);
@Native<Void Function(Pointer<Void>)>(symbol: 'cmark_iter_free')
external void _iterFree(Pointer<Void> iterator);

@Native<NodePtr Function(Int)>(symbol: 'cmark_node_new')
external NodePtr _nodeNew(int type);
@Native<Void Function(NodePtr)>(symbol: 'cmark_node_free')
external void _nodeFree(NodePtr node);
@Native<Int Function(NodePtr)>(symbol: 'cmark_node_get_type')
external int _nodeType(NodePtr node);
@Native<Pointer<Char> Function(NodePtr)>(symbol: 'cmark_node_get_type_string')
external Pointer<Char> _nodeTypeString(NodePtr node);
@Native<Pointer<Char> Function(NodePtr)>(symbol: 'cmark_node_get_literal')
external Pointer<Char> _nodeLiteral(NodePtr node);
@Native<Int Function(NodePtr, Pointer<Char>)>(symbol: 'cmark_node_set_literal')
external int _nodeSetLiteral(NodePtr node, Pointer<Char> value);
@Native<NodePtr Function(NodePtr)>(symbol: 'cmark_node_first_child')
external NodePtr _nodeFirstChild(NodePtr node);
@Native<NodePtr Function(NodePtr)>(symbol: 'cmark_node_next')
external NodePtr _nodeNext(NodePtr node);
@Native<Void Function(NodePtr)>(symbol: 'cmark_node_unlink')
external void _nodeUnlink(NodePtr node);
@Native<Int Function(NodePtr, NodePtr)>(symbol: 'cmark_node_insert_before')
external int _nodeInsertBefore(NodePtr node, NodePtr sibling);
@Native<Int Function(NodePtr, NodePtr)>(symbol: 'cmark_node_insert_after')
external int _nodeInsertAfter(NodePtr node, NodePtr sibling);
@Native<Int Function(NodePtr, NodePtr)>(symbol: 'cmark_node_prepend_child')
external int _nodePrependChild(NodePtr node, NodePtr child);
@Native<Int Function(NodePtr, NodePtr)>(symbol: 'cmark_node_append_child')
external int _nodeAppendChild(NodePtr node, NodePtr child);
@Native<Int Function(NodePtr)>(symbol: 'cmark_node_get_heading_level')
external int _headingLevel(NodePtr node);
@Native<Int Function(NodePtr)>(symbol: 'cmark_node_get_start_line')
external int _startLine(NodePtr node);
@Native<Pointer<Char> Function(NodePtr)>(symbol: 'cmark_node_get_fence_info')
external Pointer<Char> _fenceInfo(NodePtr node);
@Native<Pointer<Char> Function(NodePtr)>(symbol: 'cmark_node_get_url')
external Pointer<Char> _url(NodePtr node);
@Native<Int Function(NodePtr)>(symbol: 'cmark_node_get_list_type')
external int _listType(NodePtr node);
@Native<Int Function(NodePtr)>(symbol: 'cmark_node_get_list_start')
external int _listStart(NodePtr node);
@Native<Int Function(NodePtr)>(symbol: 'cmark_node_get_list_tight')
external int _listTight(NodePtr node);

@Native<Uint16 Function(NodePtr)>(symbol: 'cmark_gfm_extensions_get_table_columns')
external int _tableColumns(NodePtr node);
@Native<Pointer<Uint8> Function(NodePtr)>(symbol: 'cmark_gfm_extensions_get_table_alignments')
external Pointer<Uint8> _tableAlignments(NodePtr node);
@Native<Int Function(NodePtr)>(symbol: 'cmark_gfm_extensions_get_table_row_is_header')
external int _tableRowIsHeader(NodePtr node);
@Native<Bool Function(NodePtr)>(symbol: 'cmark_gfm_extensions_get_tasklist_item_checked')
external bool _taskChecked(NodePtr node);

final class _Mem extends Struct {
  external Pointer<NativeFunction<Pointer<Void> Function(Size, Size)>> calloc;
  external Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>, Size)>> realloc;
  external Pointer<NativeFunction<Void Function(Pointer<Void>)>> free;
}

/// Memory for strings passed to cmark comes from cmark's own allocator, so no libc binding is needed and the
/// same allocator frees what cmark returns, on Windows too.
final _mem = _allocator().ref;
final _calloc = _mem.calloc.asFunction<Pointer<Void> Function(int, int)>();
final _free = _mem.free.asFunction<void Function(Pointer<Void>)>();

Pointer<Char> _cString(String value) {
  final bytes = utf8.encode(value);
  final pointer = _calloc(bytes.length + 1, 1).cast<Uint8>();
  pointer.asTypedList(bytes.length + 1)
    ..setAll(0, bytes)
    ..[bytes.length] = 0;
  return pointer.cast();
}

String _string(Pointer<Char> pointer) {
  if (pointer == nullptr) return '';
  final bytes = pointer.cast<Uint8>();
  var length = 0;
  while (bytes[length] != 0) {
    length++;
  }
  return utf8.decode(bytes.asTypedList(length), allowMalformed: true);
}

String _takeString(Pointer<Char> pointer) {
  final value = _string(pointer);
  if (pointer != nullptr) _free(pointer.cast());
  return value;
}

/// A cmark node. Valid while its document is alive (inside [Cmark.withDocument]).
extension type const Node(NodePtr pointer) {
  static Node? of(NodePtr pointer) => pointer == nullptr ? null : Node(pointer);
  static Node create(int type) => Node(_nodeNew(type));

  int get type => _nodeType(pointer);
  String get typeName => _string(_nodeTypeString(pointer));
  String get literal => _string(_nodeLiteral(pointer));
  set literal(String value) {
    final c = _cString(value);
    _nodeSetLiteral(pointer, c);
    _free(c.cast());
  }

  Node? get firstChild => of(_nodeFirstChild(pointer));
  Node? get next => of(_nodeNext(pointer));
  Iterable<Node> get children sync* {
    var child = firstChild;
    while (child != null) {
      final following = child.next;
      yield child;
      child = following;
    }
  }

  void unlink() => _nodeUnlink(pointer);
  void free() => _nodeFree(pointer);
  void remove() {
    unlink();
    free();
  }

  void insertBefore(Node sibling) => _nodeInsertBefore(pointer, sibling.pointer);
  void insertAfter(Node sibling) => _nodeInsertAfter(pointer, sibling.pointer);
  void prependChild(Node child) => _nodePrependChild(pointer, child.pointer);
  void appendChild(Node child) => _nodeAppendChild(pointer, child.pointer);

  int get headingLevel => _headingLevel(pointer);
  int get startLine => _startLine(pointer);
  String get fenceInfo => _string(_fenceInfo(pointer));
  String get url => _string(_url(pointer));
  bool get orderedList => _listType(pointer) == _orderedList;
  int get listStart => _listStart(pointer);
  bool get listTight => _listTight(pointer) != 0;

  int get tableColumns => _tableColumns(pointer);
  /// Column alignments: 'l', 'c', 'r' or 0 per column.
  List<int> get tableAlignments {
    final columns = tableColumns;
    final pointerToAlignments = _tableAlignments(pointer);
    if (pointerToAlignments == nullptr) return List.filled(columns, 0);
    return List.of(pointerToAlignments.asTypedList(columns));
  }

  bool get tableRowIsHeader => _tableRowIsHeader(pointer) != 0;
  bool get taskChecked => _taskChecked(pointer);

  /// Every node in document order, collected before the caller changes the tree.
  List<Node> descendants() {
    final nodes = <Node>[];
    final iterator = _iterNew(pointer);
    try {
      while (true) {
        final event = _iterNext(iterator);
        if (event == _eventDone) break;
        if (event == _eventEnter) nodes.add(Node(_iterNode(iterator)));
      }
    } finally {
      _iterFree(iterator);
    }
    return nodes;
  }
}

abstract final class Cmark {
  static const extensions = ['table', 'strikethrough', 'autolink', 'tagfilter', 'tasklist'];
  static const options = CmarkOption.unsafe | CmarkOption.footnotes | CmarkOption.githubPreLang;

  static T withDocument<T>(String markdown, T Function(Node root, ParserPtr parser) body) {
    _ensureRegistered();
    final parser = _parserNew(options);
    try {
      for (final name in extensions) {
        final c = _cString(name);
        final extension = _findExtension(c);
        _free(c.cast());
        if (extension != nullptr) _attachExtension(parser, extension);
      }
      final bytes = utf8.encode(markdown);
      final buffer = _calloc(bytes.length + 1, 1).cast<Uint8>();
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      _parserFeed(parser, buffer.cast(), bytes.length);
      _free(buffer.cast());
      final root = Node(_parserFinish(parser));
      try {
        return body(root, parser);
      } finally {
        root.free();
      }
    } finally {
      _parserFree(parser);
    }
  }

  static String renderHtml(Node root, ParserPtr parser) =>
      _takeString(_renderHtml(root.pointer, options, _parserExtensions(parser)));

  static String renderPlaintext(Node root) => _takeString(_renderPlaintext(root.pointer, options, 0));
}
