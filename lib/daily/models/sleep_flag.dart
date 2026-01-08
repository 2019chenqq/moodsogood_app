enum SleepFlag {
  good,
  ok,
  earlyWake,
  dreams,
  lightSleep,
  fragmented,
  insufficient,
  initInsomnia,
  interrupted,
  nocturia,
}

// 睡眠標記顯示用
String sleepFlagLabel(SleepFlag f) {
  switch (f) {
    case SleepFlag.good:
      return '優';
    case SleepFlag.ok:
      return '良好';
    case SleepFlag.earlyWake:
      return '早醒';
    case SleepFlag.dreams:
      return '多夢';
    case SleepFlag.lightSleep:
      return '淺眠';
    case SleepFlag.nocturia:
      return '夜尿';
    case SleepFlag.fragmented:
      return '睡睡醒醒';
    case SleepFlag.insufficient:
      return '睡眠不足';
    case SleepFlag.initInsomnia:
      return '入睡困難 (躺超過 30 分鐘才入睡)';
    case SleepFlag.interrupted:
      return '睡眠中斷 (醒來後超過 30 分鐘才又入睡)';
  }
}
