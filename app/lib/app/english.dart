/// English interface text, keyed by the Russian text the code is written with (the same idea as mica's table).
///
/// The Russian text is the source: it is what the code passes to a label, so a missing entry shows Russian instead of
/// a blank or a key. Write English in the lowercase style the product uses; the capital style raises the first letter
/// of each sentence at draw time. A key with `{name}` placeholders matches any text that fills them, which lets a
/// sentence with a file name or a count in it be translated after the Russian one was assembled. A placeholder takes
/// the text as it is, so a file name is never translated; a part that has an English form of its own (a format name)
/// is put into the Russian sentence already translated.
///
/// Documents, file names and paths are never passed through this table.
abstract final class English {
  static const table = <String, String>{
    // Start window
    'читалка и редактор Markdown': 'reader and editor for Markdown',
    'новый файл': 'new file',
    'открыть…': 'open…',
    'или перетащите сюда файл .md': 'or drop a .md file here',
    'недавние': 'recent',
    'настройки': 'settings',

    // Dialogs and errors
    'понятно': 'got it',
    'отмена': 'cancel',
    'сохранить': 'save',
    'не сохранять': 'don’t save',
    'сохранить изменения?': 'save changes?',
    'изменения в документе «{name}» будут потеряны, если их не сохранить': 'changes in “{name}” will be lost if you don’t save them',
    'вернуть сохранённую версию?': 'revert to the saved version?',
    'несохранённые изменения в документе «{name}» будут потеряны': 'unsaved changes in “{name}” will be lost',
    'вернуть версию': 'revert',
    'сохранить в формате {format}?': 'save as {format}?',
    'файл «{name}» будет собран заново из текста: шрифты, цвета, картинки, колонтитулы и примечания не сохранятся; копия в Markdown оставит исходный файл без изменений':
        'file “{name}” will be rebuilt from its text: fonts, colors, images, headers, footers and comments won’t be kept; a copy as Markdown leaves the original file unchanged',
    'копия в Markdown': 'copy as Markdown',
    'не удалось открыть файл': 'could not open the file',
    'файл «{name}» не найден': 'file “{name}” was not found',
    'не удалось сохранить документ': 'could not save the document',
    'не удалось вернуть сохранённую версию': 'could not revert to the saved version',
    'не удалось экспортировать: {format}': 'could not export: {format}',
    'не удалось напечатать': 'could not print',
    'экспорт: {format}': 'export: {format}',
    'экспортировать': 'export',
    'пусто: оформленный текст появится здесь': 'empty: the formatted text will appear here',

    // Errors that come from the converters and the host
    'в файле нет текста документа Word': 'the file has no Word document text',
    'файл не является архивом ZIP': 'the file is not a ZIP archive',
    'оглавление архива ZIP повреждено': 'the directory of the ZIP archive is damaged',
    'запись «{name}» архива ZIP повреждена': 'entry “{name}” of the ZIP archive is damaged',
    'запись «{name}» сжата неподдерживаемым способом': 'entry “{name}” uses an unsupported compression method',
    'файл не похож на документ RTF': 'the file doesn’t look like an RTF document',
    'файл PDF не создан': 'the PDF file was not created',
    'нет окна': 'no window',
    'не удалось создать страницу для печати': 'could not create the page for printing',
    'эта версия WebView2 не умеет сохранять PDF': 'this version of WebView2 can’t save PDF',
    'не удалось записать файл PDF': 'could not write the PDF file',
    'эта версия WebView2 не умеет печатать': 'this version of WebView2 can’t print',

    // Document window
    'содержание': 'outline',
    'содержание ({shortcut})': 'outline ({shortcut})',
    'режим': 'mode',
    'чтение': 'read',
    'правка': 'edit',
    'изменён': 'edited',
    'идёт экспорт': 'exporting',
    'экспорт и сохранение': 'export and save',
    'файл ещё не сохранён': 'the file is not saved yet',
    'здесь появятся\nзаголовки документа': 'the document’s headings\nwill appear here',
    'пустой документ': 'empty document',
    'без названия': 'untitled',
    'Без названия': 'Untitled',
    'Без названия {n}': 'Untitled {n}',

    // Export menu and formats
    'экспорт': 'export',
    'веб-страница HTML': 'web page, HTML',
    'документ PDF': 'document, PDF',
    'документ Word': 'document, Word',
    'текст RTF': 'text, RTF',
    'простой текст': 'plain text',
    'текст': 'text',
    'сохранить как Markdown…': 'save as Markdown…',
    'напечатать…': 'print…',

    // Find and replace
    'найти': 'find',
    'нет': 'none',
    '{n} из {m}': '{n} of {m}',
    'назад': 'previous',
    'далее': 'next',
    'готово': 'done',
    'заменить на': 'replace with',
    'заменить': 'replace',
    'все': 'all',

    // Editing: the / menu and the context menu
    'заголовок': 'heading',
    'подзаголовок': 'subheading',
    'список': 'list',
    'нумерация': 'numbered list',
    'задача': 'task',
    'цитата': 'quote',
    'код': 'code',
    'линия': 'divider',
    'ссылка': 'link',
    'жирный': 'bold',
    'курсив': 'italic',
    'таблица': 'table',
    'вырезать': 'cut',
    'скопировать': 'copy',
    'вставить': 'paste',
    'выбрать все': 'select all',

    // Window buttons (Windows)
    'свернуть': 'minimize',
    'восстановить': 'restore',
    'развернуть': 'maximize',
    'закрыть': 'close',

    // Settings
    'оформление': 'appearance',
    'типографика': 'typography',
    'тема': 'theme',
    'система': 'system',
    'светлая': 'light',
    'тёмная': 'dark',
    'язык': 'language',
    'язык интерфейса': 'interface language',
    'материал оболочки': 'shell material',
    'прозрачность действует только на оболочку окна': 'transparency applies to the window shell only',
    'матовое стекло': 'frosted glass',
    'прозрачность': 'transparency',
    'иконка приложения': 'app icon',
    'угольная': 'charcoal',
    'каменная': 'stone',
    'синяя': 'blue',
    'зелёная': 'green',
    'лавандовая': 'lavender',
    'терракотовая': 'terracotta',
    'иконка меняется в Dock, в Finder и в переключателе программ и сохраняется после выхода':
        'the icon changes in the Dock, in Finder and in the app switcher, and stays after you quit',
    'иконка меняется на панели задач, в меню «Пуск» и в ярлыках и сохраняется после выхода':
        'the icon changes on the taskbar, in the Start menu and in shortcuts, and stays after you quit',
    'текст интерфейса': 'interface text',
    'регистр текста': 'letter case',
    'со строчной': 'lowercase',
    'С прописной': 'Capitalized',
    'документ': 'document',
    'размер применяется к чтению и правке': 'size applies to reading and editing',
    'размер текста': 'text size',
    'сбросить': 'reset',
    'версия': 'version',
    'читалка и редактор Markdown для macOS. открывайте документы, редактируйте их и экспортируйте в другие форматы.':
        'a reader and editor for Markdown on macOS. open documents, edit them and export to other formats.',
    'читалка и редактор Markdown для Windows. открывайте документы, редактируйте их и экспортируйте в другие форматы.':
        'a reader and editor for Markdown on Windows. open documents, edit them and export to other formats.',
  };

  static final _patterns = <({RegExp pattern, List<String> names, String english})>[
    for (final entry in table.entries)
      if (entry.key.contains('{')) _compile(entry.key, entry.value),
  ];

  static ({RegExp pattern, List<String> names, String english}) _compile(String russian, String english) {
    final names = <String>[];
    final source = StringBuffer('^');
    var last = 0;
    for (final match in RegExp(r'\{(\w+)\}').allMatches(russian)) {
      source.write(RegExp.escape(russian.substring(last, match.start)));
      source.write(r'([\s\S]+?)');
      names.add(match[1]!);
      last = match.end;
    }
    source
      ..write(RegExp.escape(russian.substring(last)))
      ..write(r'$');
    return (pattern: RegExp(source.toString()), names: names, english: english);
  }

  /// The English text for a Russian source text, or the text itself when the table has no entry for it. A text
  /// that is not authored interface text (a file name, a heading) is simply not in the table and comes back as is.
  static String translate(String russian) {
    final exact = table[russian];
    if (exact != null) return exact;
    for (final entry in _patterns) {
      final match = entry.pattern.firstMatch(russian);
      if (match == null) continue;
      var result = entry.english;
      for (var i = 0; i < entry.names.length; i++) {
        final value = match[i + 1]!;
        result = result.replaceAll('{${entry.names[i]}}', value);
      }
      return result;
    }
    return russian;
  }
}
