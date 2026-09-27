import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/domain/models/message_segment.dart';

/// 正文内嵌元素的解析测试。
///
/// 用例里的样本全部来自**官方文档原文或真机日志**，不是自己编的：
/// `faceType` 那条甚至不在官方文档里，正是线上抓到的那一份。
void main() {
  List<MessageSegment> parse(String content, [Map<String, String> mentions = const {}]) =>
      MessageContentParser.parse(content, mentions: mentions);

  group('@ 某人', () {
    test('旧格式 <@openid> 能命中昵称', () {
      // 真机日志原文：群聊消息内容就是这一串十六进制
      final segments = parse(
        '<@CA87605D7C22D7BA4863B86754D1876D>',
        {'CA87605D7C22D7BA4863B86754D1876D': '在下百香果'},
      );

      expect(segments, hasLength(1));
      expect(segments.single.kind, MessageSegmentKind.mention);
      expect(segments.single.text, '@在下百香果');
      expect(segments.single.resolved, isTrue);
    });

    test('新格式 <qqbot-at-user id="…" /> 能命中昵称', () {
      // 官方 9.7 节给出的新格式（旧格式标注「即将弃用」）
      final segments = parse(
        '你好 <qqbot-at-user id="A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4" /> 在吗',
        {'A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4': '小明'},
      );

      expect(segments.map((e) => e.kind), [
        MessageSegmentKind.text,
        MessageSegmentKind.mention,
        MessageSegmentKind.text,
      ]);
      expect(segments[1].text, '@小明');
      expect(segments[0].text, '你好 ');
      expect(segments[2].text, ' 在吗');
    });

    test('拿不到昵称时退化为通用占位，而不是显示 openid', () {
      final segments = parse('<@CA87605D7C22D7BA4863B86754D1876D>');

      expect(segments.single.text, '@某人');
      expect(segments.single.resolved, isFalse);
      // 原始 id 仍保留，排障时要靠它比对事件里的 mentions
      expect(segments.single.token, 'CA87605D7C22D7BA4863B86754D1876D');
    });

    test('id 大小写不一致也能命中', () {
      // openid 本身不区分大小写，正文里的大小写不保证与 mentions 一致
      final segments = parse(
        '<@ca87605d7c22d7ba4863b86754d1876d>',
        {'CA87605D7C22D7BA4863B86754D1876D': '在下百香果'},
      );
      expect(segments.single.text, '@在下百香果');
    });

    test('一次 @ 多个人，顺序原样保留', () {
      final segments = parse(
        '<@AAA> 和 <@BBB> 一起',
        {'AAA': '甲', 'BBB': '乙'},
      );
      expect(segments.map((e) => e.text).join(), '@甲 和 @乙 一起');
    });

    test('@ 全部成员', () {
      final segments = parse('<qqbot-at-everyone />');
      expect(segments.single.kind, MessageSegmentKind.mentionEveryone);
      expect(segments.single.text, '@全体成员');
    });
  });

  group('表情', () {
    test('真机抓到的 faceType 标签渲染为中性标签', () {
      // 真机日志原文（官方文档里没有这种形式，因此不去猜图片地址）
      final segments = parse('<faceType=6,faceId="0",ext="eyJ0ZXh0IjoiIn0=">');

      expect(segments, hasLength(1));
      expect(segments.single.kind, MessageSegmentKind.face);
      expect(segments.single.text, '[表情]');
      expect(segments.single.token, 'type=6,id=0');
    });

    test('faceType 与 faceId 顺序互换、字段增减都不影响识别', () {
      final segments = parse('<faceType=1,faceId="14",extra="x">');
      expect(segments.single.kind, MessageSegmentKind.face);
      expect(segments.single.token, 'type=1,id=14');
    });

    test('频道体系的 <emoji:id> 也认', () {
      final segments = parse('<emoji:4>');
      expect(segments.single.kind, MessageSegmentKind.face);
      expect(segments.single.token, '4');
    });
  });

  group('不该被吞掉的内容', () {
    test('用户真的打了一串尖括号时原样保留', () {
      // 这是最关键的一条：宁可少解析，也不能把用户的正文改掉
      const content = '这个 <abc> 是什么意思？还有 a<b 这种';
      final segments = parse(content);
      expect(segments.map((e) => e.text).join(), content);
    });

    test('空内容与 null 都返回空列表', () {
      expect(parse(''), isEmpty);
      expect(MessageContentParser.parse(null), isEmpty);
    });

    test('纯文本只有一个片段', () {
      final segments = parse('你个猪咪');
      expect(segments, hasLength(1));
      expect(segments.single.isText, isTrue);
      expect(segments.single.text, '你个猪咪');
    });
  });

  group('其它内嵌元素', () {
    test('指令标签渲染为 /文本', () {
      final segments = parse('<qqbot-cmd-enter text="帮助" />');
      expect(segments.single.kind, MessageSegmentKind.command);
      expect(segments.single.text, '/帮助');
    });

    test('参数指令优先用 show，没有则回退 text', () {
      final withShow = parse(
        '<qqbot-cmd-input text="/a" show="查询天气" reference="false" />',
      );
      expect(withShow.single.text, '/查询天气');

      final withoutShow = parse('<qqbot-cmd-input text="/b" />');
      expect(withoutShow.single.text, '/b');
    });

    test('子频道引用只露 id 尾部', () {
      final segments = parse('<#1234567890>');
      expect(segments.single.kind, MessageSegmentKind.channel);
      expect(segments.single.text, '#…567890');
    });

    test('不认识但确实是官方元素时给中性标签', () {
      final segments = parse('<qqbot-something-new a="1" />');
      expect(segments.single.kind, MessageSegmentKind.unknownElement);
      expect(segments.single.text, '[元素]');
    });
  });

  group('组合场景', () {
    test('文字 + @ + 表情 + 文字能正确切分', () {
      final segments = parse(
        '收到 <@AAA> 的 <faceType=6,faceId="0"> 消息',
        {'AAA': '小明'},
      );

      expect(segments.map((e) => e.kind), [
        MessageSegmentKind.text,
        MessageSegmentKind.mention,
        MessageSegmentKind.text,
        MessageSegmentKind.face,
        MessageSegmentKind.text,
      ]);
      expect(segments.map((e) => e.text).join(), '收到 @小明 的 [表情] 消息');
    });

    test('相邻的两个标签之间不会插入空文字片段', () {
      final segments = parse('<@AAA><@BBB>', {'AAA': '甲', 'BBB': '乙'});
      expect(segments, hasLength(2));
      expect(segments.every((e) => !e.isText), isTrue);
    });

    test('结尾的标签也能被切出来', () {
      final segments = parse('你看 <@AAA>', {'AAA': '甲'});
      expect(segments, hasLength(2));
      expect(segments.last.kind, MessageSegmentKind.mention);
    });
  });
}
