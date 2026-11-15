// Compiles the vendored cmark-gfm (the parser github.com uses) into a native library for the FFI bindings in
// lib/src/cmark.dart. The same sources build with clang on macOS and MSVC on Windows.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const _core = [
  'arena', 'blocks', 'buffer', 'cmark', 'cmark_ctype', 'commonmark', 'footnotes', 'houdini_href_e',
  'houdini_html_e', 'houdini_html_u', 'html', 'inlines', 'iterator', 'latex', 'linked_list', 'man', 'map', 'node',
  'plaintext', 'plugin', 'references', 'registry', 'render', 'scanners', 'syntax_extension', 'utf8', 'xml',
];
const _extensions = ['autolink', 'core-extensions', 'ext_scanners', 'strikethrough', 'table', 'tagfilter', 'tasklist'];

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    const root = 'third_party/cmark-gfm';
    await CBuilder.library(
      name: 'cmark_gfm',
      assetName: 'src/cmark.dart',
      sources: [
        for (final name in _core) '$root/src/$name.c',
        for (final name in _extensions) '$root/extensions/$name.c',
      ],
      includes: ['$root/src', '$root/src/include', '$root/extensions', '$root/extensions/include'],
      // Exports the API from the DLL on Windows; elsewhere the headers already mark it visible.
      defines: {'libcmark_gfm_EXPORTS': null},
    ).run(input: input, output: output);
  });
}
