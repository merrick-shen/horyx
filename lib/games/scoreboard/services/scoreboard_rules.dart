/// 计分器规则引擎（纯静态逻辑，无 UI 依赖）
/// 与 GomokuRules 同层：页面只管状态与交互，规则判定统一收敛于此
/// 规则要点：
/// - 赛制为 BO 多数局：BO3 需赢 2 局、BO5 需赢 3 局；设置页仅允许奇数局数
///   （偶数局打满后总比分可能相同，无法产生整场胜方），公式对奇数恰为多数局
/// - 每局胜负：先到达胜利分且满足领先分差的一方赢下本局；
///   leadBy 为 0 时差值条件恒成立（到分即胜），为 2 即乒乓球/羽毛球的 deuce 规则
abstract final class ScoreboardRules {
  /// 赢下整场所需局数
  static int gamesToWin(int bestOf) => bestOf ~/ 2 + 1;

  /// 某方得分是否赢下当前局
  ///
  /// [score] 得分方分数，[opp] 对方分数
  /// [winScore] 每局胜利比分，[leadBy] 领先获胜分差
  static bool winsGame(int score, int opp, int winScore, int leadBy) =>
      score >= winScore && score - opp >= leadBy;
}
