/// 五子棋规则引擎（纯静态逻辑，无 UI 依赖）
/// 本地对局页与联机控制器共用，保证两侧规则永远同源
/// （此前两份独立实现行为一致，但改规则时会静默分叉）。
/// 规则要点：
/// - 落子序列索引奇偶决定颜色：偶索引 = 黑（先手），奇索引 = 白
/// - 五连即胜：横、竖、两条斜线任一方向连成 >= 5 子
///   （六连及以上同样判胜，长连不禁手）
abstract final class GomokuRules {
  /// 判定刚落一子后是否形成五连
  ///
  /// [moves] 已生效落子序列（含刚落的这手）
  /// [boardSize] 棋盘路数（越界视为无子）
  /// [col]/[row] 刚落子的位置
  /// [black] 刚落的子是否为黑色
  static bool hasFiveInRow(
    List<(int, int)> moves,
    int boardSize,
    int col,
    int row,
    bool black,
  ) {
    // 一次性构建位置→是否黑子索引：序列索引奇偶即颜色（偶=黑），
    // 四方向延伸的每步查询降为 O(1)，整体复杂度从 O(n²) 降为 O(n)
    // （19 路满盘 361 手时原实现约 13 万次比较，现仅建一次索引）
    final isBlackAt = <(int, int), bool>{
      for (var i = 0; i < moves.length; i++) moves[i]: i.isEven,
    };
    const dirs = [(1, 0), (0, 1), (1, 1), (1, -1)];
    for (final (dx, dy) in dirs) {
      var count = 1;
      // 沿正负两个方向延伸计数；索引未命中（含越界点）即视为无子
      for (final sign in [1, -1]) {
        var c = col + dx * sign;
        var r = row + dy * sign;
        while (c >= 0 && c < boardSize && r >= 0 && r < boardSize
            && isBlackAt[(c, r)] == black) {
          count++;
          c += dx * sign;
          r += dy * sign;
        }
      }
      if (count >= 5) return true;
    }
    return false;
  }
}
