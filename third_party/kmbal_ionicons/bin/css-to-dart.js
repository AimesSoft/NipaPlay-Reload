// Generate Dart source from CSS
// https://www.npmjs.com/package/svgtofont

const fs = require('fs');

// const kDartKeywords = [
//   'abstract', 'else', 'import', 'super', 'as', 'enum', 'in', 'switch',
//   'assert', 'export', 'interface', 'sync', 'async', 'extends', 'is',
//   'this', 'await', 'extension', 'library', 'throw', 'break', 'external',
//   'mixin', 'true', 'case', 'factory', 'new', 'try', 'class', 'final',
//   'catch', 'false', 'null', 'typedef', 'on', 'var', 'const', 'finally',
//   'operator', 'void', 'continue', 'for', 'part', 'while', 'covariant',
//   'Function', 'rethrow', 'with', 'default', 'get', 'return', 'yield',
//   'deferred', 'hide', 'set', 'do', 'if', 'show', 'dynamic', 'implements',
//   'static',
// ];

// const kRegexSCSS = /-(.*):before { content: "\\(.*)"; }/g;
const kRegexSCSS = /\.Ionicons\-(.*)::before.*"\\(.*)\";/g;

const args = process.argv.slice(2);
if (args.length < 2) {
  console.log('Usage: ./node css-to-dart.js <input-icons-tsv> <output-icon-data-dart>');
  process.exit(1);
}

const mappingFile = args[0];
const outputDarFile = args[1];

const stream = fs.createWriteStream(outputDarFile)

// Data
stream.write("import 'package:flutter/widgets.dart';\n\n");

stream.write('/// A description of an icon fulfilled by a font glyph.\n');
stream.write('class IoniconsData extends IconData {\n');
stream.write('  const IoniconsData(int code)\n');
stream.write('      : super(\n');
stream.write('          code,\n');
stream.write("          fontFamily: 'Ionicons',\n");
stream.write("          fontPackage: 'kmbal_ionicons',\n");
stream.write('        );\n');
stream.write('}\n\n');

stream.write('/// Use with the Icon class to show specific icons.\n');
stream.write('class Ionicons {\n');

/// Parse
console.log('Parsing:', mappingFile);
const data = fs.readFileSync(mappingFile, { encoding: 'utf8' });
const mapping = {};
let counter = 0;
const matches = data.matchAll(kRegexSCSS);

for (const match of matches) {
  if (match.length !== 3) {
    throw new Error('Invalid match');
  }
  let name = match[1];
  const code = match[2];

  stream.write(`  /// ${name}\n`); // origin name
  mapping[name] = `0x${code}`;

  name = name.toLowerCase().replaceAll('-', '_');
  // name = name
  //   .replaceAll('default', 'default_icon')
  //   .replaceAll(' ', '_')
  //   .replaceAll('.', '_')
  //   .replaceAll(',', '')
  //   .replaceAll('(', '')
  //   .replaceAll(')', '')
  //   .replaceAll('-', '')
  //   .replaceAll('\+', '_plus')
  //   .replaceAll('#', '_sharp')
  //   .replaceAll('&', 'n');

  stream.write(`  static const ${name} = IoniconsData(0x${code});\n\n`);

  counter++;
}

stream.write('}\n');

// Mapping
stream.write('\n');
stream.write('const ioniconsMapping = ');
stream.write(JSON.stringify(mapping, null, 2));
stream.write(';\n');

stream.end();

console.log('Write source to:', outputDarFile);
console.log('Total:', counter);
