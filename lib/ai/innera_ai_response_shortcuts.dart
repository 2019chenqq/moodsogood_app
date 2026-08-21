List<String> inneraAiResponseShortcuts(String rawText) {
  final text = rawText.replaceAll(RegExp(r'\s+'), '');
  if (text.isEmpty) return const [];

  // Check sleep-pattern questions first so phrases such as "sleep time" do
  // not get mistaken for a question about when an event happened.
  const sleepPatterns = ['難入睡', '容易醒', '早醒', '睡睡醒醒'];
  final matchedSleepPatterns =
      sleepPatterns.where((pattern) => text.contains(pattern)).length;
  final asksForSleepType = matchedSleepPatterns >= 2 ||
      (RegExp(r'(哪一種|哪種|類型|比較像)').hasMatch(text) &&
          RegExp(r'(睡不好|睡眠問題|入睡|容易醒|早醒|睡睡醒醒)').hasMatch(text));
  if (asksForSleepType) {
    return const ['難入睡', '容易醒', '太早醒', '睡睡醒醒', '其他'];
  }

  final explicitlyAsksForFivePointRating =
      RegExp(r'1(?:～|到|至|[-–—])5').hasMatch(text) &&
          RegExp(r'(程度|強度|幾分|評分|分數)').hasMatch(text);
  if (explicitlyAsksForFivePointRating) {
    return List.generate(5, (index) => '${index + 1} / 5');
  }

  final explicitlyAsksWhenItHappened = RegExp(
    r'(什麼時候發生|何時發生|'
    r'這件事.{0,8}什麼時候|(症狀|感覺|不舒服).{0,8}什麼時候開始|'
    r'發生在今天|發生時間是|是在?現在還是|'
    r'現在.{0,8}還是.{0,8}(稍早|早上|下午))',
  ).hasMatch(text);
  if (explicitlyAsksWhenItHappened) {
    return const ['現在', '今天早上', '今天下午', '其他時間'];
  }

  return const [];
}
