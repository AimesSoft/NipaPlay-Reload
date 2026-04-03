import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/danmaku_xml_utils.dart';

void main() {
  group('convertBilibiliXmlDanmakuToJson', () {
    test('parses standard bilibili xml payloads', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<i>
  <d p="1.5,1,25,16777215,1700000000,0,0,0">hello &amp; world</d>
  <d p="2.0,5,30,16711680,1700000001,0,0,0">top</d>
</i>
''';

      final result = convertBilibiliXmlDanmakuToJson(xml);
      final comments = result['comments'] as List<dynamic>;

      expect(result['count'], 2);
      expect(comments[0]['t'], 1.5);
      expect(comments[0]['c'], 'hello & world');
      expect(comments[0]['y'], 'scroll');
      expect(comments[0]['r'], 'rgb(255,255,255)');
      expect(comments[1]['y'], 'top');
      expect(comments[1]['fontSize'], 30);
      expect(comments[1]['originalType'], 5);
    });

    test('falls back for malformed xml text nodes', () {
      const malformedXml =
          '<i><d p="3,1,25,16777215,1700000002,0,0,0">1 < 2</d></i>';

      final result = convertBilibiliXmlDanmakuToJson(malformedXml);
      final comments = result['comments'] as List<dynamic>;

      expect(result['count'], 1);
      expect(comments.single['c'], '1 < 2');
      expect(comments.single['t'], 3.0);
    });
  });
}
