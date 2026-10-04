import 'package:lpinyin/lpinyin.dart';
import 'package:characters/characters.dart';

const morseAlphabet = {
  'A': '.-',
  'B': '-...',
  'C': '-.-.',
  'D': '-..',
  'E': '.',
  'F': '..-.',
  'G': '--.',
  'H': '....',
  'I': '..',
  'J': '.---',
  'K': '-.-',
  'L': '.-..',
  'M': '--',
  'N': '-.',
  'O': '---',
  'P': '.--.',
  'Q': '--.-',
  'R': '.-.',
  'S': '...',
  'T': '-',
  'U': '..-',
  'V': '...-',
  'W': '.--',
  'X': '-..-',
  'Y': '-.--',
  'Z': '--..',
  '0': '-----',
  '1': '.----',
  '2': '..---',
  '3': '...--',
  '4': '....-',
  '5': '.....',
  '6': '-....',
  '7': '--...',
  '8': '---..',
  '9': '----.',
  '.': '.-.-.-',
  ',': '--..--',
  '?': '..--..',
  '!': '-.-.--',
  ':': '---...',
  '-': '-....-',
  '/': '-..-.',
  '@': '.--.-.',
};

String convertBase(String text, int from, int to) {
  if (from < 2 || from > 36 || to < 2 || to > 36) {
    throw const FormatException('进制须为 2—36');
  }
  if (text.trim().isEmpty || text.length > 4096) {
    throw const FormatException('请输入整数，最多 4096 位');
  }
  final value = BigInt.tryParse(text.trim(), radix: from);
  if (value == null) throw FormatException('输入不符合 $from 进制，暂不支持小数');
  return value.toRadixString(to).toUpperCase();
}

String chineseNumber(String input, {bool money = false}) {
  final match = RegExp(r'^([+-]?)(\d{1,16})(?:\.(\d{1,12}))?$')
      .firstMatch(input.trim());
  if (match == null) throw const FormatException('请输入数字，整数最多 16 位，小数最多 12 位');
  final fraction = match[3] ?? '';
  if (money && fraction.length > 2) {
    throw const FormatException('金额最多两位小数，请先确认金额');
  }
  final digits = money ? '零壹贰叁肆伍陆柒捌玖' : '零一二三四五六七八九';
  final small = money ? ['', '拾', '佰', '仟'] : ['', '十', '百', '千'];
  const large = ['', '万', '亿', '兆'];
  var number = BigInt.parse(match[2]!);
  var index = 0;
  var result = '';
  var gap = false;
  while (number > BigInt.zero) {
    final block = (number % BigInt.from(10000)).toInt();
    if (block == 0) {
      if (result.isNotEmpty) gap = true;
    } else {
      var group = '', zero = false;
      for (var place = 3; place >= 0; place--) {
        final divisor = [1, 10, 100, 1000][place];
        final digit = block ~/ divisor % 10;
        if (digit == 0) {
          if (group.isNotEmpty) zero = true;
        } else {
          if (zero) group += digits[0];
          group += digits[digit] + small[place];
          zero = false;
        }
      }
      result = group + large[index] + (gap ? digits[0] : '') + result;
      gap = block < 1000;
    }
    number ~/= BigInt.from(10000);
    index++;
  }
  if (result.isEmpty) result = digits[0];
  if (!money && result.startsWith('一十')) result = result.substring(1);
  if (money) {
    result += '元';
    final decimal = fraction.padRight(2, '0');
    final jiao = int.parse(decimal[0]), fen = int.parse(decimal[1]);
    if (jiao == 0 && fen == 0) {
      result += '整';
    } else {
      if (jiao > 0) result += '${digits[jiao]}角';
      if (fen > 0) result += '${jiao == 0 ? digits[0] : ''}${digits[fen]}分';
    }
  } else if (fraction.isNotEmpty) {
    result += '点${fraction.split('').map((c) => digits[int.parse(c)]).join()}';
  }
  final nonzero =
      BigInt.parse(match[2]!) != BigInt.zero ||
      fraction.contains(RegExp('[1-9]'));
  return '${match[1] == '-' && nonzero ? '负' : ''}$result';
}

String morse(String input, {bool decode = false}) {
  if (decode) {
    final reverse = {for (final e in morseAlphabet.entries) e.value: e.key};
    return input
        .trim()
        .split(RegExp(r'\s*/\s*'))
        .map(
          (word) => word.trim().split(RegExp(r'\s+')).map((code) {
            if (code.isEmpty) return '';
            if (!reverse.containsKey(code)) {
              throw FormatException('无法识别电码：$code');
            }
            return reverse[code]!;
          }).join(),
        )
        .join(' ');
  }
  return input
      .toUpperCase()
      .trim()
      .split(RegExp(r'\s+'))
      .map(
        (word) => word
            .split('')
            .map((c) {
              if (!morseAlphabet.containsKey(c)) {
                throw FormatException('不支持字符：$c（支持英文、数字和常用标点）');
              }
              return morseAlphabet[c]!;
            })
            .join(' '),
      )
      .join(' / ');
}

String raisedDigits(String input, {bool sub = false}) {
  const normal = '0123456789+-=()';
  final alternate = sub ? '₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎' : '⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾';
  return input
      .split('')
      .map((c) => normal.contains(c) ? alternate[normal.indexOf(c)] : c)
      .join();
}

String miniEnglish(String input) {
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  const small = 'ᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀꜱᴛᴜᴠᴡxʏᴢ';
  return input
      .split('')
      .map(
        (c) => letters.contains(c.toLowerCase())
            ? small[letters.indexOf(c.toLowerCase())]
            : c,
      )
      .join();
}

List<String> splitWords(String input) =>
    RegExp(r'[A-Za-z0-9]+|[^\s]').allMatches(input).map((m) => m[0]!).toList();

String pinyinText(String input, String format, Map<int, String> overrides) {
  final style = format == '声调数字'
      ? PinyinFormat.WITH_TONE_NUMBER
      : format == '无声调' || format == '首字母'
      ? PinyinFormat.WITHOUT_TONE
      : PinyinFormat.WITH_TONE_MARK;
  final chars = input.characters.toList(), result = StringBuffer();
  final separator = format == '首字母' ? '' : ' ';
  var index = 0;
  while (index < chars.length) {
    final c = chars[index];
    if (overrides.containsKey(index)) {
      final chosen = overrides[index]!;
      result.write(format == '首字母' ? chosen[0] : chosen);
      result.write(separator);
      index++;
      continue;
    }
    final candidates = PinyinHelper.convertToPinyinArray(c, style);
    if (candidates.isEmpty) {
      result.write(c);
      index++;
      continue;
    }
    final phrase = PinyinHelper.convertToMultiPinyin(
      chars.skip(index).join(),
      '|',
      style,
    );
    if (phrase != null &&
        !overrides.keys.any(
          (key) => key >= index && key < index + phrase.word!.length,
        )) {
      final values = phrase.pinyin!
          .split('|')
          .where((v) => v.isNotEmpty)
          .toList();
      result.write(
        format == '首字母' ? values.map((v) => v[0]).join() : values.join(' '),
      );
      result.write(separator);
      index += phrase.word!.length;
    } else {
      result.write(format == '首字母' ? candidates.first[0] : candidates.first);
      result.write(separator);
      index++;
    }
  }
  return result.toString().trimRight();
}
