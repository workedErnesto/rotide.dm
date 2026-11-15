/// Words and reading time for the outline footer.
final class TextStats {
  TextStats(String text) : this._count(text);

  TextStats._count(String text)
      : words = _words(text),
        characters = text.runes.length;

  final int words;
  final int characters;

  /// Minutes at 200 words a minute, at least one for a non-empty text.
  int get readingMinutes => words == 0 ? 0 : ((words / 200).round()).clamp(1, 1 << 30);

  static final _wordy = RegExp(r'[\p{L}\p{M}\p{N}]', unicode: true);

  static int _words(String text) {
    var words = 0;
    var inWord = false;
    for (final rune in text.runes) {
      final wordy = rune < 0x80 ? _asciiWordy(rune) : _wordy.hasMatch(String.fromCharCode(rune));
      if (wordy && !inWord) words += 1;
      inWord = wordy;
    }
    return words;
  }

  static bool _asciiWordy(int c) => (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  @override
  bool operator ==(Object other) => other is TextStats && other.words == words && other.characters == characters;

  @override
  int get hashCode => Object.hash(words, characters);
}
