import 'package:flutter_test/flutter_test.dart';
import 'package:horyx/shared/audio/game_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未加载条目播放不抛错（静默返回）', () {
    expect(
      () => GameAudio.play('assets/audio/common/win.ogg'),
      returnsNormally,
    );
  });

  test('预载失败静默降级：不抛出且后续播放保持静默', () async {
    // 测试环境无 SoLoud 原生库，初始化必然失败，正好覆盖降级路径
    await GameAudio.preload(const ['assets/audio/common/win.ogg']);
    expect(
      () => GameAudio.play('assets/audio/common/win.ogg'),
      returnsNormally,
    );
  });
}
