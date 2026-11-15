/// GitHub emoji shortcodes (`:tada:`) most used in READMEs and changelogs. Unknown codes stay as written.
abstract final class Emoji {
  static const table = <String, String>{
    "+1": "👍", "-1": "👎", "thumbsup": "👍", "thumbsdown": "👎", "ok_hand": "👌", "clap": "👏", "wave": "👋",
    "raised_hands": "🙌", "pray": "🙏", "muscle": "💪", "point_right": "👉", "point_left": "👈", "point_up": "☝️",
    "point_down": "👇", "eyes": "👀", "handshake": "🤝", "v": "✌️", "smile": "😄", "smiley": "😃", "grinning": "😀",
    "blush": "😊", "wink": "😉", "joy": "😂", "laughing": "😆", "sweat_smile": "😅", "heart_eyes": "😍",
    "sunglasses": "😎", "thinking": "🤔", "neutral_face": "😐", "confused": "😕", "cry": "😢", "sob": "😭",
    "scream": "😱", "rage": "😡", "sleeping": "😴", "upside_down_face": "🙃", "nerd_face": "🤓", "partying_face": "🥳",
    "exploding_head": "🤯", "skull": "💀", "ghost": "👻", "robot": "🤖", "alien": "👽", "see_no_evil": "🙈",
    "heart": "❤️", "orange_heart": "🧡", "yellow_heart": "💛", "green_heart": "💚", "blue_heart": "💙",
    "purple_heart": "💜", "black_heart": "🖤", "broken_heart": "💔", "sparkling_heart": "💖", "100": "💯",
    "tada": "🎉", "confetti_ball": "🎊", "sparkles": "✨", "star": "⭐", "star2": "🌟", "dizzy": "💫", "boom": "💥",
    "fire": "🔥", "zap": "⚡", "rocket": "🚀", "airplane": "✈️", "car": "🚗", "ship": "🚢", "globe_with_meridians": "🌐",
    "earth_americas": "🌎", "sunny": "☀️", "cloud": "☁️", "umbrella": "☔", "snowflake": "❄️", "rainbow": "🌈",
    "ocean": "🌊", "seedling": "🌱", "evergreen_tree": "🌲", "deciduous_tree": "🌳", "cactus": "🌵", "herb": "🌿",
    "four_leaf_clover": "🍀", "rose": "🌹", "sunflower": "🌻", "cherry_blossom": "🌸", "apple": "🍎", "coffee": "☕",
    "beer": "🍺", "pizza": "🍕", "cake": "🍰", "cookie": "🍪", "bug": "🐛", "beetle": "🪲", "ant": "🐜", "bee": "🐝",
    "snake": "🐍", "turtle": "🐢", "whale": "🐳", "penguin": "🐧", "cat": "🐱", "dog": "🐶", "unicorn": "🦄",
    "crab": "🦀", "rabbit": "🐰", "panda_face": "🐼", "chart_with_upwards_trend": "📈", "chart_with_downwards_trend": "📉",
    "bar_chart": "📊", "memo": "📝", "pencil": "📝", "pencil2": "✏️", "book": "📖", "books": "📚", "bookmark": "🔖",
    "page_facing_up": "📄", "page_with_curl": "📃", "scroll": "📜", "clipboard": "📋", "pushpin": "📌",
    "round_pushpin": "📍", "paperclip": "📎", "link": "🔗", "file_folder": "📁", "open_file_folder": "📂",
    "card_index_dividers": "🗂️", "calendar": "📆", "date": "📅", "package": "📦", "inbox_tray": "📥",
    "outbox_tray": "📤", "email": "📧", "envelope": "✉️", "mailbox": "📫", "bell": "🔔", "no_bell": "🔕",
    "loudspeaker": "📢", "mega": "📣", "speech_balloon": "💬", "thought_balloon": "💭", "mag": "🔍",
    "mag_right": "🔎", "bulb": "💡", "flashlight": "🔦", "wrench": "🔧", "hammer": "🔨", "hammer_and_wrench": "🛠️",
    "nut_and_bolt": "🔩", "gear": "⚙️", "toolbox": "🧰", "magnet": "🧲", "test_tube": "🧪", "microscope": "🔬",
    "telescope": "🔭", "satellite": "📡", "computer": "💻", "desktop_computer": "🖥️", "keyboard": "⌨️",
    "iphone": "📱", "floppy_disk": "💾", "cd": "💿", "battery": "🔋", "electric_plug": "🔌", "lock": "🔒",
    "unlock": "🔓", "key": "🔑", "closed_lock_with_key": "🔐", "shield": "🛡️", "warning": "⚠️", "no_entry": "⛔",
    "no_entry_sign": "🚫", "construction": "🚧", "rotating_light": "🚨", "triangular_flag_on_post": "🚩",
    "checkered_flag": "🏁", "white_check_mark": "✅", "heavy_check_mark": "✔️", "ballot_box_with_check": "☑️",
    "x": "❌", "negative_squared_cross_mark": "❎", "heavy_plus_sign": "➕", "heavy_minus_sign": "➖",
    "question": "❓", "grey_question": "❔", "exclamation": "❗", "grey_exclamation": "❕", "bangbang": "‼️",
    "information_source": "ℹ️", "arrow_right": "➡️", "arrow_left": "⬅️", "arrow_up": "⬆️", "arrow_down": "⬇️",
    "arrows_counterclockwise": "🔄", "repeat": "🔁", "recycle": "♻️", "new": "🆕", "free": "🆓", "up": "🆙",
    "cool": "🆒", "ok": "🆗", "sos": "🆘", "copyright": "©️", "registered": "®️", "tm": "™️", "hourglass": "⌛",
    "hourglass_flowing_sand": "⏳", "stopwatch": "⏱️", "alarm_clock": "⏰", "watch": "⌚", "moneybag": "💰",
    "dollar": "💵", "credit_card": "💳", "gem": "💎", "trophy": "🏆", "medal_sports": "🏅", "1st_place_medal": "🥇",
    "dart": "🎯", "game_die": "🎲", "video_game": "🎮", "art": "🎨", "musical_note": "🎵", "notes": "🎶",
    "headphones": "🎧", "microphone": "🎤", "movie_camera": "🎥", "camera": "📷", "tv": "📺", "gift": "🎁",
    "balloon": "🎈", "crown": "👑", "lipstick": "💄", "ring": "💍", "house": "🏠", "office": "🏢",
    "building_construction": "🏗️", "lipstick_kiss": "💋", "zzz": "💤", "poop": "💩", "hankey": "💩",
    "lady_beetle": "🐞", "truck": "🚚", "bricks": "🧱", "label": "🏷️", "speaking_head": "🗣️",
    "busts_in_silhouette": "👥", "bust_in_silhouette": "👤", "man_technologist": "👨‍💻", "woman_technologist": "👩‍💻",
    "technologist": "🧑‍💻", "construction_worker": "👷", "lock_with_ink_pen": "🔏", "pen": "🖊️",
    "triangular_ruler": "📐", "straight_ruler": "📏", "abacus": "🧮", "jigsaw": "🧩", "thread": "🧵",
    "goal_net": "🥅", "ambulance": "🚑", "adhesive_bandage": "🩹", "pill": "💊", "syringe": "💉", "dna": "🧬",
    "chart": "💹", "heavy_dollar_sign": "💲", "green_book": "📗", "blue_book": "📘", "orange_book": "📙",
    "closed_book": "📕", "notebook": "📓", "ledger": "📒", "newspaper": "📰", "label_tag": "🏷️", "flags": "🎏",
    "white_flag": "🏳️", "black_flag": "🏴", "rainbow_flag": "🏳️‍🌈", "ru": "🇷🇺", "us": "🇺🇸", "gb": "🇬🇧", "uk": "🇬🇧",
    "de": "🇩🇪", "fr": "🇫🇷", "jp": "🇯🇵", "cn": "🇨🇳", "kr": "🇰🇷", "it": "🇮🇹", "es": "🇪🇸",
  };

  static final _nameChar = RegExp(r'^[\p{L}\p{N}_+\-]+$', unicode: true);

  /// Text with known `:code:` replaced, or null when nothing changed.
  static String? replacingShortcodes(String text) {
    final result = StringBuffer();
    var changed = false;
    var rest = text;
    while (true) {
      final open = rest.indexOf(':');
      if (open < 0) break;
      final close = rest.indexOf(':', open + 1);
      if (close < 0) break;
      final name = rest.substring(open + 1, close);
      final emoji = name.isNotEmpty && _nameChar.hasMatch(name) ? table[name] : null;
      if (emoji != null) {
        result
          ..write(rest.substring(0, open))
          ..write(emoji);
        changed = true;
        rest = rest.substring(close + 1);
      } else {
        // The closing colon may open the next code (`a:b :tada:`).
        result.write(rest.substring(0, open + 1));
        rest = rest.substring(open + 1);
      }
    }
    result.write(rest);
    return changed ? result.toString() : null;
  }
}
