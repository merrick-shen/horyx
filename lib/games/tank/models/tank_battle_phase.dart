/// 战场阶段（与本地对局状态机一一对应）
enum TankBattlePhase {
  /// 对局进行中（含开局摇杆可动）
  playing,

  /// 击毁后的结算展示期：战场继续推进，残弹可命中（双杀可能发生）
  settling,

  /// 计分定格期：全场静止展示比分，到点开新一局
  frozen;

  /// 编码为载荷字符串
  String toPayload() => name;

  /// 从载荷解码；未知值返回 null
  static TankBattlePhase? tryParse(Object? value) {
    for (final phase in TankBattlePhase.values) {
      if (phase.name == value) return phase;
    }
    return null;
  }
}
