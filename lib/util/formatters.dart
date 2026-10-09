/// 展示格式化工具
library;

/// 格式化日期 yyyy-MM-dd HH:mm
String fmtDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// 格式化 VIP 到期时间戳
String fmtExpire(int ts) {
  if (ts <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// 格式化 VIP 到期时间戳（中文年月日，如 2027年05月21日）
String fmtExpireCn(int ts) {
  final p = fmtExpire(ts).split('-');
  return p.length == 3 ? '${p[0]}年${p[1]}月${p[2]}日' : fmtExpire(ts);
}
