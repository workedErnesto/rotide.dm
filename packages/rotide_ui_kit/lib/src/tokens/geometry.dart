// Ported from mica (shared/tokens.json) through the Swift Geometry.swift: the same chrome, spacing and concentric radii.

/// Window chrome geometry. The macOS window buttons sit on the vertical centre of [bar].
abstract final class Chrome {
  /// Top bar.
  static const double bar = 44;
  static const double lightsX = 14;
  static const double lightsStep = 20;

  /// Width reserved for the macOS window buttons, measured from the window edge.
  static const double lightsInset = 84;

  /// Leading icon tile of a two-line list row.
  static const double rowIcon = 30;

  /// Outline sidebar; its width changes by dragging the card edge within [sidebarMin]...[sidebarMax].
  static const double sidebar = 232;
  static const double sidebarMin = 180;
  static const double sidebarMax = 360;

  /// Narrower windows hide the outline for the moment.
  static const double narrowWindow = 760;

  /// Readable line length of the editor; wider cards centre the text column.
  static const double editorColumn = 760;

  /// Smallest document window.
  static const double minWidth = 560;
  static const double minHeight = 420;
}

/// Spacing scale.
abstract final class Space {
  static const double micro = 4;
  static const double small = 8;
  static const double normal = 12;
  static const double section = 20;
  static const double large = 32;
}

/// Concentric radii: an inner shape uses the outer radius minus the padding between them.
abstract final class Radii {
  /// Inset between the window edge and the document cards.
  static const double gutter = 8;

  /// Document card. Matches the macOS window corner, so the card reads as a window inside the window.
  static const double card = 10;

  /// Menus and floating panels.
  static const double panel = 16;

  /// Padding inside a panel; rows inside it use panel - panelPadding.
  static const double panelPadding = 6;

  /// panel - panelPadding.
  static const double row = 10;

  /// Segmented track and its thumb (track - 2 pt padding).
  static const double track = 10;

  /// track - 2.
  static const double thumb = 8;
  static const double icon = 8;

  /// Window-level cards. panel + 2.
  static const double modal = 18;
}
