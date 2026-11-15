/// Heading anchors as GitHub makes them (github-slugger): lowercase, punctuation dropped, every space a hyphen,
/// letters of any script kept, repeats numbered `-1`, `-2`.
final class Slugger {
  final _seen = <String, int>{};
  static final _kept = RegExp(r'[\p{L}\p{M}\p{N}_\-]', unicode: true);

  String slug(String title) {
    final base = StringBuffer();
    for (final rune in title.toLowerCase().runes) {
      final character = String.fromCharCode(rune);
      if (character == ' ') {
        base.write('-');
      } else if (_kept.hasMatch(character)) {
        base.write(character);
      }
    }
    final root = base.toString();
    var slug = root;
    final count = _seen[root];
    if (count != null) {
      var next = count;
      do {
        next += 1;
        slug = '$root-$next';
      } while (_seen.containsKey(slug));
      _seen[root] = next;
    }
    _seen.putIfAbsent(slug, () => 0);
    return slug;
  }
}
