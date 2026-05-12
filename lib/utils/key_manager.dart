import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';


// ── compute() 需要頂層 function ──
encrypt_lib.Key _deriveKeyIsolate(List<String> args) {
  return KeyManager._deriveKeySync(args[0], args[1]);
}
 
class KeyManager {
 
  // ─────────────────────────────────────────
  //  PIN → AES 金鑰（PBKDF2，背景執行）
  // ─────────────────────────────────────────
 
  static encrypt_lib.Key _deriveKeySync(String pin, String salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(
      Uint8List.fromList(utf8.encode(salt)),
      200000,
      32,
    ));
    return encrypt_lib.Key(pbkdf2.process(Uint8List.fromList(utf8.encode(pin))));
  }
 
  /// PIN + salt → AES-256 金鑰（在背景 isolate 執行，不卡 UI）
  static Future<encrypt_lib.Key> deriveKey(String pin, String salt) async {
    return compute(_deriveKeyIsolate, [pin, salt]);
  }
 
  // ─────────────────────────────────────────
  //  備援金鑰 → AES 金鑰
  // ─────────────────────────────────────────
 
  /// 用備援金鑰字串（12 個單字）推導 AES-256 金鑰
  /// 與 deriveKey() 使用不同前綴，確保即使 PIN 碰巧與備援金鑰相同，
  /// 也不會產生相同的 AES 金鑰。
  static Future<encrypt_lib.Key> deriveKeyFromRecoveryKey(
    String recoveryKey,
    String salt,
  ) async {
    // 加上固定前綴區分 PIN 與備援金鑰的來源
    const prefix = 'recovery-key:';
    return compute(_deriveKeyIsolate, [prefix + recoveryKey, salt]);
  }
 
  // ─────────────────────────────────────────
  //  備援金鑰產生 & 驗證
  // ─────────────────────────────────────────
 
  /// 產生 12 個隨機英文單字組成的備援金鑰
  /// 格式：'MOON-FIRE-TREE-BLUE-JAZZ-WIND-ROSE-GOLD-LAKE-STAR-DAWN-RAIN'
  /// 熵值：256 個單字 × 12 個 = log2(256^12) = 96 bits
  static String generateRecoveryKey() {
    final random = Random.secure();
    final words = List.generate(
      12,
      (_) => _wordList[random.nextInt(_wordList.length)],
    );
    return words.join('-');
  }
 
  /// 計算備援金鑰的 SHA-256 雜湊（存到 Firebase 用來驗證，不存明文）
  static String hashRecoveryKey(String recoveryKey) {
    final bytes = utf8.encode(recoveryKey.toUpperCase().trim());
    return sha256.convert(bytes).toString();
  }
 
  /// 驗證用戶輸入的備援金鑰是否與雲端儲存的雜湊吻合
  static bool verifyRecoveryKey(String inputKey, String storedHash) {
    final inputHash = hashRecoveryKey(inputKey);
    return inputHash == storedHash;
  }
 
  // ─────────────────────────────────────────
  //  Salt 產生
  // ─────────────────────────────────────────
 
  static String generateSecureSalt() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64UrlEncode(values);
  }
 
  // ─────────────────────────────────────────
  //  備援金鑰單字表（256 個單字 = 8 bits/word）
  // ─────────────────────────────────────────
 
  static const List<String> _wordList = [
    'ABLE', 'ACID', 'AGED', 'ALSO', 'AREA', 'ARMY', 'AWAY', 'BABY',
    'BACK', 'BALL', 'BAND', 'BANK', 'BASE', 'BATH', 'BEAN', 'BEAR',
    'BEAT', 'BELL', 'BELT', 'BEST', 'BIRD', 'BITE', 'BLUE', 'BOAT',
    'BODY', 'BOLD', 'BOLT', 'BOND', 'BONE', 'BOOK', 'BOOM', 'BORN',
    'BOWL', 'BURN', 'BUSH', 'BUSY', 'CAGE', 'CAKE', 'CALM', 'CARD',
    'CARE', 'CART', 'CASE', 'CASH', 'CAVE', 'CELL', 'CHIP', 'CITY',
    'CLAY', 'CLUB', 'COAL', 'COAT', 'CODE', 'COIN', 'COLD', 'COOK',
    'COOL', 'COPY', 'CORE', 'CORN', 'COST', 'CREW', 'CROP', 'CUBE',
    'CURL', 'CUTE', 'DARK', 'DART', 'DATA', 'DATE', 'DAWN', 'DEAD',
    'DEAL', 'DEAR', 'DEEP', 'DEER', 'DENY', 'DESK', 'DIET', 'DIRT',
    'DISK', 'DIVE', 'DOCK', 'DONE', 'DOOR', 'DOSE', 'DOWN', 'DRAW',
    'DROP', 'DRUM', 'DUCK', 'DUNE', 'DUSK', 'DUST', 'DUTY', 'EACH',
    'EARN', 'EASE', 'EAST', 'EDGE', 'EMIT', 'EVEN', 'EVIL', 'FACE',
    'FACT', 'FAIL', 'FAIR', 'FALL', 'FAME', 'FARM', 'FAST', 'FATE',
    'FILE', 'FILL', 'FILM', 'FIND', 'FIRE', 'FIRM', 'FISH', 'FLAG',
    'FLAT', 'FLIP', 'FLOW', 'FOAM', 'FOLD', 'FOLK', 'FOND', 'FOOD',
    'FOOT', 'FORD', 'FORK', 'FORM', 'FORT', 'FREE', 'FUEL', 'FULL',
    'FUND', 'FUSE', 'GALE', 'GAME', 'GATE', 'GAVE', 'GAZE', 'GEAR',
    'GENE', 'GIFT', 'GIRL', 'GIVE', 'GLAD', 'GLOW', 'GLUE', 'GOLD',
    'GOLF', 'GOOD', 'GRAB', 'GRAY', 'GRID', 'GRIN', 'GRIP', 'GROW',
    'GULF', 'GUST', 'HALF', 'HALL', 'HAND', 'HANG', 'HARD', 'HARM',
    'HATE', 'HAVE', 'HAWK', 'HAZE', 'HEAD', 'HEAL', 'HEAT', 'HEEL',
    'HELD', 'HELM', 'HELP', 'HERE', 'HERO', 'HIGH', 'HILL', 'HINT',
    'HIRE', 'HOLD', 'HOLE', 'HOME', 'HOOD', 'HOOK', 'HOPE', 'HORN',
    'HOST', 'HOUR', 'HUGE', 'HUNG', 'HUNT', 'HURT', 'IDEA', 'IRIS',
    'IRON', 'ISLE', 'ITEM', 'JADE', 'JOIN', 'JUMP', 'JUST', 'KEEN',
    'KEPT', 'KIND', 'KING', 'KISS', 'KNEE', 'KNEW', 'KNOT', 'LACE',
    'LAKE', 'LAMP', 'LAND', 'LANE', 'LAST', 'LATE', 'LEAD', 'LEAF',
    'LEAN', 'LEAP', 'LEFT', 'LEND', 'LENS', 'LIFT', 'LIKE', 'LIME',
    'LINE', 'LION', 'LIST', 'LIVE', 'LOCK', 'LONE', 'LONG', 'LOOK',
    'LORD', 'LOSS', 'LOST', 'LOUD', 'LOVE', 'LUCK', 'LURE', 'MADE',
    'MAIL', 'MAIN', 'MAKE', 'MANY', 'MARK', 'MASK', 'MASS', 'MAST',
  ];
}