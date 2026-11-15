import 'markdown_renderer.dart' show Html;

/// A piece of code and its token kind (`k` keyword, `s` string, `c` comment, `n` number or literal, `f` function,
/// `t` type, `v` variable, `tag`, `attr`, `key`, `meta`, `ins`, `del`, `hunk`), null for plain text.
final class Token {
  const Token(this.kind, this.text);
  final String? kind;
  final String text;

  @override
  bool operator ==(Object other) => other is Token && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'Token($kind, ${text.replaceAll('\n', r'\n')})';
}

/// Syntax highlighting of fenced code blocks, done once at render time so the preview, HTML export and PDF share it.
/// A small lexer per language family: comments, strings, numbers, keywords, literals, types, function calls.
/// Unknown languages come out escaped and uncoloured, as on GitHub.
abstract final class Highlighter {
  static String html(String code, String? language) => tokens(code, language)
      .map((token) => token.kind == null ? Html.escape(token.text) : '<span class="tok-${token.kind}">${Html.escape(token.text)}</span>')
      .join();

  static List<Token> tokens(String code, String? language) {
    final spec = language == null ? null : _Language.find(language);
    if (spec == null) return [Token(null, code)];
    final sink = _TokenSink();
    switch (spec.kind) {
      case _Kind.markup:
        _markup(code.runes.toList(), sink);
      case _Kind.diff:
        _diff(code, sink);
      case _Kind.code:
        _Lexer(spec, code.runes.toList()).run(sink);
    }
    return sink.tokens;
  }

  static void _diff(String code, _TokenSink sink) {
    final lines = code.split('\n');
    for (var index = 0; index < lines.length; index++) {
      if (index > 0) sink.add(null, '\n');
      final line = lines[index];
      if (line.startsWith('+++') || line.startsWith('---')) {
        sink.add('meta', line);
      } else if (line.startsWith('+')) {
        sink.add('ins', line);
      } else if (line.startsWith('-')) {
        sink.add('del', line);
      } else if (line.startsWith('@@')) {
        sink.add('hunk', line);
      } else {
        sink.add(null, line);
      }
    }
  }

  /// HTML, XML and SVG: tags, attribute names, attribute values and comments.
  static void _markup(List<int> chars, _TokenSink sink) {
    var i = 0;
    String piece(int from, int to) => String.fromCharCodes(chars, from, to);
    bool startsAt(String token, int at) {
      final runes = token.runes.toList();
      if (at + runes.length > chars.length) return false;
      for (var k = 0; k < runes.length; k++) {
        if (chars[at + k] != runes[k]) return false;
      }
      return true;
    }

    String takeUntil(String end) {
      final length = end.runes.length;
      var j = i;
      while (j < chars.length) {
        if (startsAt(end, j)) {
          j += length;
          break;
        }
        j += 1;
      }
      final end_ = j < chars.length ? j : chars.length;
      final text = piece(i, end_);
      i = end_;
      return text;
    }

    while (i < chars.length) {
      final c = chars[i];
      if (c == _lt && startsAt('<!--', i)) {
        sink.add('c', takeUntil('-->'));
      } else if (c == _lt && i + 1 < chars.length && (_isLetter(chars[i + 1]) || '/!?'.codeUnits.contains(chars[i + 1]))) {
        var j = i + 1;
        while (j < chars.length && (_isLetter(chars[j]) || _isNumber(chars[j]) || '/!?-:_.'.codeUnits.contains(chars[j]))) {
          j += 1;
        }
        sink
          ..add(null, '<')
          ..add('tag', piece(i + 1, j));
        i = j;
        while (i < chars.length && chars[i] != _gt) {
          final ch = chars[i];
          if (ch == _dquote || ch == _squote) {
            var k = i + 1;
            while (k < chars.length && chars[k] != ch) {
              k += 1;
            }
            k = k + 1 < chars.length ? k + 1 : chars.length;
            sink.add('s', piece(i, k));
            i = k;
          } else if (_isLetter(ch) || ch == 0x5F || ch == 0x3A || ch == 0x40) {
            var k = i;
            while (k < chars.length && (_isLetter(chars[k]) || _isNumber(chars[k]) || '-_:.@'.codeUnits.contains(chars[k]))) {
              k += 1;
            }
            sink.add('attr', piece(i, k));
            i = k;
          } else {
            sink.add(null, String.fromCharCode(ch));
            i += 1;
          }
        }
        if (i < chars.length) {
          sink.add(null, '>');
          i += 1;
        }
      } else {
        sink.add(null, String.fromCharCode(c));
        i += 1;
      }
    }
  }
}

const _lt = 0x3C, _gt = 0x3E, _dquote = 0x22, _squote = 0x27, _newline = 0x0A;

final _letter = RegExp(r'\p{L}', unicode: true);
final _number = RegExp(r'\p{N}', unicode: true);
final _upper = RegExp(r'\p{Lu}', unicode: true);

bool _isLetter(int c) {
  if (c < 0x80) return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  return _letter.hasMatch(String.fromCharCode(c));
}

bool _isNumber(int c) {
  if (c < 0x80) return c >= 0x30 && c <= 0x39;
  return _number.hasMatch(String.fromCharCode(c));
}

bool _isUpper(int c) {
  if (c < 0x80) return c >= 0x41 && c <= 0x5A;
  return _upper.hasMatch(String.fromCharCode(c));
}

/// Collects tokens, joining neighbours of the same kind so plain text does not come out one character at a time.
final class _TokenSink {
  final tokens = <Token>[];
  void add(String? kind, String text) {
    if (text.isEmpty) return;
    if (tokens.isNotEmpty && tokens.last.kind == kind) {
      tokens[tokens.length - 1] = Token(kind, tokens.last.text + text);
    } else {
      tokens.add(Token(kind, text));
    }
  }
}

enum _Kind { code, markup, diff }

final class _Language {
  const _Language({
    this.kind = _Kind.code,
    this.lineComments = const [],
    this.blockComment,
    this.quotes = const {'"', "'"},
    this.multilineQuotes = const {},
    this.tripleQuotes = false,
    this.keywords = const {},
    this.literals = const {'true', 'false', 'null'},
    this.caseInsensitive = false,
    this.capitalizedTypes = true,
    this.dollarVariables = false,
    this.attributePrefixes = const {},
    this.keys = false,
  });

  final _Kind kind;
  final List<String> lineComments;
  final (String, String)? blockComment;
  final Set<String> quotes;

  /// Strings that may span lines: backticks, triple quotes.
  final Set<String> multilineQuotes;
  final bool tripleQuotes;
  final Set<String> keywords;
  final Set<String> literals;
  final bool caseInsensitive;
  final bool capitalizedTypes;

  /// `$name` variables (shell, PHP, Perl-like).
  final bool dollarVariables;

  /// `@attribute`, `@decorator`, `#directive` at the start of a word.
  final Set<String> attributePrefixes;

  /// JSON, YAML, TOML: a string or word right before `:`/`=` is a key.
  final bool keys;

  static Set<String> words(String list) => list.split(' ').where((word) => word.isNotEmpty).toSet();

  static final cFamily = words('if else for while do switch case default break continue return goto sizeof typedef '
      'struct union enum static const extern volatile register inline void char short int long float double signed '
      'unsigned auto');

  static final _cache = <String, _Language?>{};

  static _Language? find(String name) => _cache.putIfAbsent(name, () => _make(name));

  static _Language? _make(String name) {
    switch (name) {
      case 'swift':
        return _Language(
            lineComments: ['//'], blockComment: ('/*', '*/'), quotes: {'"'}, tripleQuotes: true,
            keywords: words('actor as associatedtype async await break case catch class continue default defer deinit '
                'do else enum extension fallthrough fileprivate final for func guard if import in indirect init inout '
                'internal is lazy let mutating nonisolated open operator override private protocol public repeat '
                'required rethrows return self Self some any static struct subscript super switch throw throws try '
                'typealias var weak where while unowned convenience dynamic optional get set willSet didSet macro '
                'consume borrowing consuming'),
            literals: {'true', 'false', 'nil'}, attributePrefixes: {'@', '#'});
      case 'js' || 'javascript' || 'jsx' || 'mjs' || 'cjs' || 'ts' || 'typescript' || 'tsx':
        return _Language(
            lineComments: ['//'], blockComment: ('/*', '*/'), quotes: {'"', "'", '`'}, multilineQuotes: {'`'},
            keywords: words('async await break case catch class const continue debugger default delete do else export '
                'extends finally for from function get if import in instanceof let new of return set static super '
                'switch this throw try typeof var void while with yield as interface type enum implements namespace '
                'declare readonly private protected public abstract keyof satisfies'),
            literals: {'true', 'false', 'null', 'undefined', 'NaN', 'Infinity'}, attributePrefixes: {'@'});
      case 'java' || 'kotlin' || 'kt' || 'kts' || 'scala' || 'groovy' || 'gradle' || 'dart' || 'cs' || 'csharp' || 'c#':
        return _Language(
            lineComments: ['//'], blockComment: ('/*', '*/'), quotes: {'"', "'"}, tripleQuotes: true,
            keywords: words('abstract assert break case catch class const continue default do else enum extends final '
                'finally for if implements import instanceof interface native new package private protected public '
                'return static super switch synchronized this throw throws transient try void volatile while var val '
                'fun object companion data sealed when is in out override open internal lateinit by init typealias '
                'suspend inline reified operator namespace using struct readonly ref out params base sealed async '
                'await yield get set late required extension mixin with def trait match implicit lazy let dynamic '
                'typeof sizeof'),
            literals: {'true', 'false', 'null', 'nil'}, attributePrefixes: {'@', '#'});
      case 'c' || 'h' || 'cpp' || 'c++' || 'cc' || 'cxx' || 'hpp' || 'objc' || 'objective-c' || 'm' || 'mm':
        return _Language(
            lineComments: ['//'], blockComment: ('/*', '*/'), quotes: {'"', "'"},
            keywords: cFamily.union(words('class namespace template typename public private protected virtual '
                'override final new delete this using try catch throw operator friend explicit mutable constexpr '
                'nullptr noexcept decltype bool auto import interface implementation end property synthesize self '
                'super id instancetype nonatomic strong weak assign')),
            literals: {'true', 'false', 'NULL', 'nullptr', 'nil', 'YES', 'NO'}, attributePrefixes: {'#', '@'});
      case 'go' || 'golang':
        return _Language(
            lineComments: ['//'], blockComment: ('/*', '*/'), quotes: {'"', "'", '`'}, multilineQuotes: {'`'},
            keywords: words('break case chan const continue default defer else fallthrough for func go goto if import '
                'interface map package range return select struct switch type var'),
            literals: {'true', 'false', 'nil', 'iota'});
      case 'rust' || 'rs':
        return _Language(
            lineComments: ['//'], blockComment: ('/*', '*/'), quotes: {'"'},
            keywords: words('as async await break const continue crate dyn else enum extern fn for if impl in let loop '
                'match mod move mut pub ref return self Self static struct super trait type unsafe use where while'),
            literals: {'true', 'false', 'None', 'Some', 'Ok', 'Err'}, attributePrefixes: {'#'});
      case 'php':
        return _Language(
            lineComments: ['//', '#'], blockComment: ('/*', '*/'),
            keywords: words('abstract and array as break callable case catch class clone const continue declare '
                'default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final '
                'finally fn for foreach function global goto if implements include include_once instanceof insteadof '
                'interface isset list match namespace new or print private protected public readonly require '
                'require_once return static switch throw trait try unset use var while yield'),
            literals: {'true', 'false', 'null', 'TRUE', 'FALSE', 'NULL'}, dollarVariables: true);
      case 'python' || 'py' || 'python3':
        return _Language(
            lineComments: ['#'], quotes: {'"', "'"}, tripleQuotes: true,
            keywords: words('and as assert async await break class continue def del elif else except finally for from '
                'global if import in is lambda nonlocal not or pass raise return try while with yield match case self '
                'cls'),
            literals: {'True', 'False', 'None'}, attributePrefixes: {'@'});
      case 'ruby' || 'rb':
        return _Language(
            lineComments: ['#'],
            keywords: words('alias and begin break case class def defined? do else elsif end ensure for if in module '
                'next not or redo rescue retry return self super then undef unless until when while yield require '
                'require_relative attr_accessor attr_reader private protected public'),
            literals: {'true', 'false', 'nil'}, attributePrefixes: {'@', ':'});
      case 'sh' || 'bash' || 'zsh' || 'shell' || 'console' || 'shellsession' || 'fish' || 'ps1' || 'powershell':
        return _Language(
            lineComments: ['#'],
            keywords: words('if then else elif fi for while until do done case esac in function return exit export '
                'local readonly unset set source alias echo cd sudo let declare shift trap eval exec'),
            literals: {}, capitalizedTypes: false, dollarVariables: true);
      case 'sql' || 'mysql' || 'postgresql' || 'postgres' || 'sqlite' || 'plsql':
        return _Language(
            lineComments: ['--'], blockComment: ('/*', '*/'),
            keywords: words('select from where and or not insert into values update set delete create table alter '
                'drop index view primary key foreign references join left right inner outer full on as group by order '
                'having limit offset distinct union all exists in between like is case when then else end begin '
                'commit rollback transaction default unique check constraint returning with asc desc if replace '
                'trigger function procedure database schema grant revoke cascade integer int text varchar char '
                'boolean date timestamp serial bigint real numeric'),
            literals: {'null', 'true', 'false'}, caseInsensitive: true, capitalizedTypes: false);
      case 'lua':
        return _Language(
            lineComments: ['--'], blockComment: ('--[[', ']]'),
            keywords: words('and break do else elseif end for function goto if in local not or repeat return then '
                'until while'),
            literals: {'true', 'false', 'nil'});
      case 'json' || 'jsonc' || 'json5' || 'geojson':
        return const _Language(
            lineComments: ['//'], blockComment: ('/*', '*/'), quotes: {'"'}, literals: {'true', 'false', 'null'},
            capitalizedTypes: false, keys: true);
      case 'yaml' || 'yml':
        return const _Language(
            lineComments: ['#'], literals: {'true', 'false', 'null', 'yes', 'no', 'on', 'off', '~'},
            capitalizedTypes: false, keys: true);
      case 'toml' || 'ini' || 'cfg' || 'conf' || 'properties' || 'env' || 'dotenv':
        return const _Language(
            lineComments: ['#', ';'], tripleQuotes: true, literals: {'true', 'false'}, capitalizedTypes: false, keys: true);
      case 'css' || 'scss' || 'sass' || 'less':
        return _Language(
            lineComments: name == 'css' ? [] : ['//'], blockComment: ('/*', '*/'),
            keywords: words('important media import supports keyframes font-face from to and not only screen print'),
            literals: {}, capitalizedTypes: false, dollarVariables: true, attributePrefixes: {'@'}, keys: true);
      case 'dockerfile' || 'docker' || 'makefile' || 'make' || 'cmake':
        return _Language(
            lineComments: ['#'],
            keywords: words('FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD '
                'STOPSIGNAL HEALTHCHECK SHELL AS ifeq ifneq ifdef ifndef else endif include define endef export'),
            literals: {}, capitalizedTypes: false, dollarVariables: true);
      case 'html' || 'xml' || 'svg' || 'xhtml' || 'plist' || 'vue' || 'svelte':
        return const _Language(kind: _Kind.markup);
      case 'diff' || 'patch':
        return const _Language(kind: _Kind.diff);
      default:
        return null;
    }
  }
}

final class _Lexer {
  _Lexer(this.spec, this.text);

  final _Language spec;
  final List<int> text;
  var i = 0;

  bool starts(String token, int index) {
    var j = index;
    for (final c in token.runes) {
      if (j >= text.length || text[j] != c) return false;
      j += 1;
    }
    return true;
  }

  bool isWord(int c) => _isLetter(c) || _isNumber(c) || c == 0x5F;
  bool has(Set<String> set, int c) => set.contains(String.fromCharCode(c));

  void emit(String? kind, int start, _TokenSink sink) => sink.add(kind, String.fromCharCodes(text, start, i));

  /// Next character that is not a space or tab after `index`.
  int? nextVisible(int index) {
    var j = index;
    while (j < text.length && (text[j] == 0x20 || text[j] == 0x09)) {
      j += 1;
    }
    return j < text.length ? text[j] : null;
  }

  void run(_TokenSink sink) {
    const colon = 0x3A, equals = 0x3D, paren = 0x28, dollar = 0x24, brace = 0x7B, closeBrace = 0x7D;
    while (i < text.length) {
      final c = text[i];
      final start = i;
      final block = spec.blockComment;
      final lineMarker = spec.lineComments
          .where((marker) => starts(marker, i))
          .where((marker) => marker != '#' || i == 0 || !isWord(text[i - 1]) && text[i - 1] != dollar)
          .firstOrNull;
      if (block != null && starts(block.$1, i)) {
        i += block.$1.length;
        while (i < text.length && !starts(block.$2, i)) {
          i += 1;
        }
        i = (i + block.$2.length).clamp(0, text.length);
        emit('c', start, sink);
      } else if (lineMarker != null) {
        while (i < text.length && text[i] != _newline) {
          i += 1;
        }
        emit('c', start, sink);
      } else if (has(spec.quotes, c) || has(spec.multilineQuotes, c)) {
        final quote = String.fromCharCode(c);
        final triple = spec.tripleQuotes && starts(quote * 3, i);
        final closing = triple ? quote * 3 : quote;
        final multiline = triple || has(spec.multilineQuotes, c);
        i += closing.length;
        while (i < text.length) {
          if (text[i] == 0x5C) {
            i = (i + 2).clamp(0, text.length);
            continue;
          }
          if (starts(closing, i)) {
            i += closing.length;
            break;
          }
          if (text[i] == _newline && !multiline) break;
          i += 1;
        }
        emit(spec.keys && nextVisible(i) == colon ? 'key' : 's', start, sink);
      } else if (_isNumber(c) && (start == 0 || !isWord(text[start - 1]))) {
        while (i < text.length && (isWord(text[i]) || (text[i] == 0x2E && i + 1 < text.length && _isNumber(text[i + 1])))) {
          i += 1;
        }
        emit('n', start, sink);
      } else if (spec.dollarVariables && c == dollar && i + 1 < text.length && (isWord(text[i + 1]) || text[i + 1] == brace)) {
        i += 1;
        if (text[i] == brace) {
          while (i < text.length && text[i] != closeBrace) {
            i += 1;
          }
          i = (i + 1).clamp(0, text.length);
        } else {
          while (i < text.length && isWord(text[i])) {
            i += 1;
          }
        }
        emit('v', start, sink);
      } else if (has(spec.attributePrefixes, c) && i + 1 < text.length && _isLetter(text[i + 1]) && (start == 0 || !isWord(text[start - 1]))) {
        i += 1;
        while (i < text.length && (isWord(text[i]) || text[i] == 0x2D)) {
          i += 1;
        }
        emit('meta', start, sink);
      } else if (_isLetter(c) || c == 0x5F) {
        while (i < text.length && (isWord(text[i]) || (spec.keys && text[i] == 0x2D))) {
          i += 1;
        }
        if (i < text.length &&
            (text[i] == 0x3F || text[i] == 0x21) &&
            spec.lineComments.length == 1 &&
            spec.lineComments.first == '#' &&
            spec.keywords.contains(String.fromCharCodes(text, start, i + 1))) {
          i += 1;
        }
        final word = String.fromCharCodes(text, start, i);
        final lookup = spec.caseInsensitive ? word.toLowerCase() : word;
        final next = nextVisible(i);
        if (spec.keys && (next == colon || next == equals) && (start == 0 || lineStart(start))) {
          emit('key', start, sink);
        } else if (spec.keywords.contains(lookup)) {
          emit('k', start, sink);
        } else if (spec.literals.contains(lookup)) {
          emit('n', start, sink);
        } else if (next == paren) {
          emit('f', start, sink);
        } else if (spec.capitalizedTypes && _isUpper(c) && word.runes.length > 1) {
          emit('t', start, sink);
        } else {
          emit(null, start, sink);
        }
      } else {
        i += 1;
        emit(null, start, sink);
      }
    }
  }

  /// Only spaces, dashes (YAML lists) or brackets between the line start and `index`.
  bool lineStart(int index) {
    var j = index - 1;
    while (j >= 0 && text[j] != _newline) {
      if (!' \t-[{,'.codeUnits.contains(text[j])) return false;
      j -= 1;
    }
    return true;
  }
}
