import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/shared/storage/game_archive_state.dart';

class _FakeState implements GameArchiveSummary {
  const _FakeState(this.summary, this.savedAt);

  factory _FakeState.fromJson(Map<String, dynamic> json) {
    return _FakeState(
      json['summary'] as String,
      DateTime.parse(json['savedAt'] as String),
    );
  }

  @override
  final String summary;
  @override
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'savedAt': savedAt.toIso8601String(),
      };
}

class _FakeArchiveStorage extends ArchiveStorage<_FakeState> {
  const _FakeArchiveStorage();

  @override
  String get gameId => '基类测试游戏';

  @override
  _FakeState fromJson(Map<String, dynamic> json) => _FakeState.fromJson(json);

  @override
  Map<String, dynamic> toJson(_FakeState state) => state.toJson();
}

class _HarnessPage extends StatefulWidget {
  const _HarnessPage({required this.setupPhase});

  final bool setupPhase;

  @override
  State<_HarnessPage> createState() => _HarnessPageState();
}

class _HarnessPageState extends GameArchiveStateBase<_HarnessPage, _FakeState> {
  @override
  ArchiveStorage<_FakeState> get archiveStorage => const _FakeArchiveStorage();

  @override
  bool get isInSetupPhase => widget.setupPhase;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  const storage = _FakeArchiveStorage();

  Future<_HarnessPageState> pumpHarness(WidgetTester tester,
      {bool setupPhase = true}) async {
    await tester.pumpWidget(
      MaterialApp(home: _HarnessPage(setupPhase: setupPhase)),
    );
    return tester.state<_HarnessPageState>(find.byType(_HarnessPage));
  }

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  testWidgets('loadSavedState 后恢复入口仅展示最新一条存档', (tester) async {
    await storage.saveArchive(
      _FakeState('旧档', DateTime(2026, 9, 1)),
    );
    await storage.saveArchive(
      _FakeState('新档', DateTime(2026, 9, 2)),
    );
    final state = await pumpHarness(tester);

    await state.loadSavedState();
    await tester.pump();

    expect(state.savedState?.summary, '新档');
    expect(state.resumedArchiveId, isNotNull);
  });

  testWidgets('无存档时 loadSavedState 不产生恢复入口', (tester) async {
    final state = await pumpHarness(tester);

    await state.loadSavedState();
    await tester.pump();

    expect(state.savedState, isNull);
    expect(state.resumedArchiveId, isNull);
  });

  testWidgets('不在设置阶段时 loadSavedState 不写入恢复入口', (tester) async {
    await storage.saveArchive(_FakeState('存档', DateTime(2026, 9, 1)));
    final state = await pumpHarness(tester, setupPhase: false);

    await state.loadSavedState();
    await tester.pump();

    expect(state.savedState, isNull);
  });

  testWidgets('恢复链路保存覆盖原档（条目数不变）', (tester) async {
    await storage.saveArchive(_FakeState('旧进度', DateTime(2026, 9, 1)));
    final state = await pumpHarness(tester);
    await state.loadSavedState();
    await tester.pump();

    final id = await state.saveCurrent(
      _FakeState('新进度', DateTime(2026, 9, 2)),
    );

    expect(id, state.resumedArchiveId);
    final summaries = await storage.loadSummaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.summary, '新进度');
    expect(summaries.single.id, id);
  });

  testWidgets('discardResumeEntry 后保存新建存档', (tester) async {
    await storage.saveArchive(_FakeState('旧进度', DateTime(2026, 9, 1)));
    final state = await pumpHarness(tester);
    await state.loadSavedState();
    await tester.pump();

    state.discardResumeEntry();
    expect(state.savedState, isNull);
    expect(state.resumedArchiveId, isNull);

    await state.saveCurrent(_FakeState('新进度', DateTime(2026, 9, 2)));

    final summaries = await storage.loadSummaries();
    expect(summaries, hasLength(2));
  });

  testWidgets('首次保存后重新绑定：后续保存继续覆盖同档', (tester) async {
    final state = await pumpHarness(tester);

    final firstId = await state
        .saveCurrent(_FakeState('第一次保存', DateTime(2026, 9, 1)));
    final secondId = await state
        .saveCurrent(_FakeState('第二次保存', DateTime(2026, 9, 2)));

    expect(secondId, firstId);
    final summaries = await storage.loadSummaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.summary, '第二次保存');
  });

  testWidgets('takeResumeEntry 返回存档并关闭入口', (tester) async {
    await storage.saveArchive(_FakeState('待恢复', DateTime(2026, 9, 1)));
    final state = await pumpHarness(tester);
    await state.loadSavedState();
    await tester.pump();

    final saved = state.takeResumeEntry();
    expect(saved?.summary, '待恢复');
    expect(state.savedState, isNull);
    expect(state.takeResumeEntry(), isNull);
  });

  testWidgets('clearCurrentArchive 删除绑定档，未绑定时无操作', (tester) async {
    await storage.saveArchive(_FakeState('进行中', DateTime(2026, 9, 1)));
    final state = await pumpHarness(tester);

    await state.clearCurrentArchive();
    expect(await storage.loadSummaries(), hasLength(1));

    await state.loadSavedState();
    await tester.pump();
    await state.clearCurrentArchive();

    expect(await storage.loadSummaries(), isEmpty);
    expect(state.resumedArchiveId, isNull);
  });
}
