import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_question_parser.dart';

void main() {
  test('AI follow-up questions are split into separate fields', () {
    expect(
      normalizeFollowUpQuestions([
        '1. 最近一週睡眠有明顯變化嗎？\n2、服藥後有不舒服嗎？',
        '3) 有沒有最想優先告訴醫師的事情？',
      ]),
      [
        '最近一週睡眠有明顯變化嗎？',
        '服藥後有不舒服嗎？',
        '有沒有最想優先告訴醫師的事情？',
      ],
    );
  });

  test('AI follow-up question splitting removes duplicates', () {
    expect(
      normalizeFollowUpQuestions([
        '1. 最近睡得如何？ 2. 是否有藥物副作用？',
        '最近睡得如何？',
      ]),
      ['最近睡得如何？', '是否有藥物副作用？'],
    );
  });

  test('decimal values do not create extra follow-up questions', () {
    expect(
      normalizeFollowUpQuestions(['最近每晚大約睡 2.5 小時嗎？']),
      ['最近每晚大約睡 2.5 小時嗎？'],
    );
  });

  test('introductory text is not treated as a follow-up question', () {
    expect(
      normalizeFollowUpQuestions([
        '1. 您好，為了更完整地了解您的狀況，請問：\n'
            '2. 近期情緒狀態是否有明顯波動或困擾？',
      ]),
      ['近期情緒狀態是否有明顯波動或困擾？'],
    );
  });
}
