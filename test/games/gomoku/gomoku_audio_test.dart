import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horyx/games/gomoku/services/gomoku_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('音效素材逐一存在且非空（防路径笔误与漏登记）', () async {
    expect(GomokuAudio.files, isNotEmpty);
    for (final path in GomokuAudio.files) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: '$path 不应为空');
    }
  });
}
