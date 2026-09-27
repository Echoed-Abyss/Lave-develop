import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/gateway/message_mapper.dart';
import 'package:lavedevelop/gateway/protocol/events/qq_event.dart';
import 'package:lavedevelop/domain/models/qq_enums.dart';

/// 事件 → 领域字段映射的回归用例。
///
/// 输入全部是**官方字段名**（`mentions` / `msg_elements` / `message_scene.ext`
/// 等，见知识库 5.2 / 5.3 节），因此这些用例同时是映射逻辑与官方文档口径的哨兵。
void main() {
  const botId = '102810595';

  QqEvent decode(String type, Map<String, dynamic> data) =>
      QqEvent.decode(type, data, id: 'event-1', seq: 1);

  group('mentions 索引', () {
    /// 官方群聊事件体里 `mentions` 是 `[]User`，且 User 具备全部标识字段。
    Map<String, dynamic> groupEvent({
      List<Map<String, dynamic>>? mentions,
    }) =>
        {
          'id': 'ROBOT1.0_msg',
          'author': {
            'id': 'AUTHORID',
            'member_openid': 'AUTHORID',
            'member_role': 'member',
            'username': '白轩',
            'bot': false,
          },
          'content': '你看看',
          'group_openid': 'GROUPOPENID',
          'message_type': 0,
          'timestamp': '2026-09-27T10:00:00+08:00',
          'mentions': ?mentions,
        };

    test('被 @ 的那四种标识都登记，正文里出现哪一个都能命中', () {
      // 官方只说明「mentions 是 []User、不含 @机器人自身」，
      // 没说正文里的 <@...> 用的是哪个字段，所以必须四个都登记。
      final event = decode('GROUP_AT_MESSAGE_CREATE', groupEvent(mentions: [
        {
          'id': 'ID0001',
          'member_openid': 'MEMBER0001',
          'user_openid': 'USER0001',
          'union_openid': 'UNION0001',
          'username': '在下百香果',
        }
      ]));

      final index = MessageMapper.mentionsOf(event);

      expect(index['id0001'], '在下百香果');
      expect(index['member0001'], '在下百香果');
      expect(index['user0001'], '在下百香果');
      expect(index['union0001'], '在下百香果');
      // key 统一小写：正文里的十六进制大小写不保证与事件一致
      expect(index.keys.every((k) => k == k.toLowerCase()), isTrue);
    });

    test('多个被 @ 的人各自成项', () {
      final event = decode('GROUP_AT_MESSAGE_CREATE', groupEvent(mentions: [
        {'id': 'AAA', 'username': '甲'},
        {'id': 'BBB', 'username': '乙'},
      ]));

      final index = MessageMapper.mentionsOf(event);
      expect(index['aaa'], '甲');
      expect(index['bbb'], '乙');
    });

    test('昵称为空的人被跳过，而不是登记成空字符串', () {
      // 官方示例里 username 就有空串（C2C 示例），
      // 登记成空串会让渲染层以为「解析成功但没名字」。
      final event = decode('GROUP_AT_MESSAGE_CREATE', groupEvent(mentions: [
        {'id': 'AAA', 'username': ''},
        {'id': 'BBB', 'username': '乙'},
      ]));

      final index = MessageMapper.mentionsOf(event);
      expect(index.containsKey('aaa'), isFalse);
      expect(index['bbb'], '乙');
    });

    test('没有 mentions 字段时返回空表', () {
      final event = decode('GROUP_AT_MESSAGE_CREATE', groupEvent());
      expect(MessageMapper.mentionsOf(event), isEmpty);
    });
  });

  group('引用消息（message_type = 103）', () {
    Map<String, dynamic> quoteEvent({
      String? refMsgIdx,
      required List<Map<String, dynamic>> elements,
    }) =>
        {
          'id': 'ROBOT1.0_msg',
          'author': {
            'id': 'AUTHORID',
            'user_openid': 'AUTHORID',
            'username': '白轩',
            'bot': false,
          },
          'content': '这个建议很有帮助，谢谢你！',
          'message_type': 103,
          'msg_elements': elements,
          'message_scene': {
            'source': 'default',
            'ext': [
              if (refMsgIdx != null) 'ref_msg_idx=$refMsgIdx',
              'msg_idx=REFIDX_SELF==',
            ],
          },
          'timestamp': '2026-09-27T10:02:00+08:00',
        };

    test('按 ref_msg_idx 精确定位被引用的那条', () {
      // 官方 5.1 示例的形态：被引用内容躺在元素的 content 上
      final event = decode('C2C_MESSAGE_CREATE', quoteEvent(
        refMsgIdx: 'REFIDX_TARGET==',
        elements: [
          {'msg_idx': 'REFIDX_OTHER==', 'content': '不该选这条'},
          {'msg_idx': 'REFIDX_TARGET==', 'content': '每天坚持阅读半小时'},
        ],
      ));

      final quote = MessageMapper.quoteOf(event, botId: botId);

      expect(quote, isNotNull);
      expect(quote!.content, '每天坚持阅读半小时');
    });

    test('没有 ref_msg_idx 时退回第一个有内容的元素', () {
      final event = decode('C2C_MESSAGE_CREATE', quoteEvent(elements: [
        {'msg_idx': 'REFIDX_A==', 'content': ''},
        {'msg_idx': 'REFIDX_B==', 'content': '有内容的那条'},
      ]));

      final quote = MessageMapper.quoteOf(event, botId: botId);

      expect(quote!.content, '有内容的那条');
    });

    test('引用块里的发送者带昵称与头像', () {
      final event = decode('C2C_MESSAGE_CREATE', quoteEvent(elements: [
        {
          'msg_idx': 'REFIDX_A==',
          'content': '被引用的原文',
          'author': {'id': 'QUOTEDAUTHOR', 'username': '在下百香果'},
        }
      ]));

      final quote = MessageMapper.quoteOf(event, botId: botId);

      expect(quote!.sender.displayName, '在下百香果');
      expect(quote.sender.scopeId, 'QUOTEDAUTHOR');
      expect(
        quote.sender.avatarUrl,
        'https://q.qlogo.cn/qqapp/$botId/QUOTEDAUTHOR/100',
      );
    });

    test('引用里的图片附件走与正文同一套归一', () {
      final event = decode('C2C_MESSAGE_CREATE', quoteEvent(elements: [
        {
          'msg_idx': 'REFIDX_A==',
          'attachments': [
            {
              'content_type': 'image/png',
              'filename': 'a.png',
              'url': 'https://example.com/a.png',
              'width': 100,
              'height': 50,
              'size': 2048,
            }
          ],
        }
      ]));

      final quote = MessageMapper.quoteOf(event, botId: botId);

      expect(quote!.attachments, hasLength(1));
      expect(quote.attachments.single.isImage, isTrue);
      expect(quote.attachments.single.filename, 'a.png');
      expect(quote.preview, '[图片]');
    });

    test('没有任何可展示元素时不构造引用块', () {
      final empty = decode('C2C_MESSAGE_CREATE', quoteEvent(elements: [
        {'msg_idx': 'REFIDX_A==', 'content': '   '},
      ]));
      expect(MessageMapper.quoteOf(empty, botId: botId), isNull);

      final none = decode('C2C_MESSAGE_CREATE', quoteEvent(elements: const []));
      expect(MessageMapper.quoteOf(none, botId: botId), isNull);
    });

    test('并行消息 / 聊天记录（101 / 102）不算引用', () {
      // 官方把 msg_elements 定义为「message_type=103 时包含被引用内容」；
      // 101/102 带 msg_elements 时那是**本条消息自己的内容**。
      // 不加这道判定的话，一条并行消息会被渲染成标着「引用」的块。
      for (final type in [101, 102]) {
        final event = decode('C2C_MESSAGE_CREATE', {
          ...quoteEvent(elements: [
            {'msg_idx': 'REFIDX_A==', 'content': '=== 消息 1 ===\n内容'},
          ]),
          'message_type': type,
        });

        expect(
          MessageMapper.quoteOf(event, botId: botId),
          isNull,
          reason: 'message_type=$type 不应被当成引用',
        );
      }
    });

    test('没有 message_type 时也不猜成引用', () {
      final raw = quoteEvent(elements: [
        {'msg_idx': 'REFIDX_A==', 'content': '内容'},
      ])..remove('message_type');

      final event = decode('C2C_MESSAGE_CREATE', raw);
      expect(MessageMapper.quoteOf(event, botId: botId), isNull);
    });

    test('引用使用当前消息的会话与场景，而不是空值', () {
      final event = decode('C2C_MESSAGE_CREATE', quoteEvent(elements: [
        {'msg_idx': 'REFIDX_A==', 'content': '原文'},
      ]));

      final quote = MessageMapper.quoteOf(event, botId: botId);

      expect(quote!.scope, ConversationScope.c2c);
      expect(quote.conversationId, 'AUTHORID');
    });
  });

  group('头像地址', () {
    Map<String, dynamic> groupEventWithAvatar(String? avatar) => {
          'id': 'ROBOT1.0_msg',
          'author': {
            'id': 'AUTHORID',
            'member_openid': 'AUTHORID',
            'username': '白轩',
            'avatar': ?avatar,
          },
          'content': 'x',
          'group_openid': 'GROUPOPENID',
          'timestamp': '2026-09-27T10:00:00+08:00',
        };

    test('事件带了 avatar 就优先用它（官方目前不给，但给了就生效）', () {
      final event = decode(
        'GROUP_AT_MESSAGE_CREATE',
        groupEventWithAvatar('https://example.com/official.png'),
      );

      expect(
        MessageMapper.avatarOf(event, botId: botId, senderId: 'AUTHORID'),
        'https://example.com/official.png',
      );
    });

    test('没带 avatar 时按 AppID + openid 拼 CDN 地址', () {
      final event = decode(
        'GROUP_AT_MESSAGE_CREATE',
        groupEventWithAvatar(null),
      );

      expect(
        MessageMapper.avatarOf(event, botId: botId, senderId: 'AUTHORID'),
        'https://q.qlogo.cn/qqapp/$botId/AUTHORID/100',
      );
    });

    test('发送者未知时不拼地址（否则只会拿到 CDN 的默认灰头像）', () {
      final event = decode(
        'GROUP_AT_MESSAGE_CREATE',
        groupEventWithAvatar(null),
      );

      expect(
        MessageMapper.avatarOf(event, botId: botId, senderId: 'unknown'),
        isNull,
      );
    });
  });

  group('附件归一', () {
    test('语音附件保留 WAV 地址与 ASR 文本', () {
      final event = decode('GROUP_AT_MESSAGE_CREATE', {
        'id': 'ROBOT1.0_msg',
        'author': {'id': 'A', 'member_openid': 'A', 'username': '白轩'},
        'content': '',
        'group_openid': 'G',
        'timestamp': '2026-09-27T10:00:00+08:00',
        'attachments': [
          {
            'content_type': 'voice',
            'filename': 'v.silk',
            'size': 4096,
            'voice_wav_url': 'https://example.com/v.wav',
            'asr_refer_text': '你好呀',
          }
        ],
      });

      final attachments = MessageMapper.attachmentsOf(event);

      expect(attachments, hasLength(1));
      expect(attachments.single.isVoice, isTrue);
      expect(attachments.single.voiceWavUrl, 'https://example.com/v.wav');
      expect(attachments.single.asrText, '你好呀');
      // 语音不是图片，摘要应显示 [语音] 而不是附件名
      expect(attachments.single.isImage, isFalse);
    });

    test('没有附件时返回空列表而不是 null', () {
      final event = decode('GROUP_AT_MESSAGE_CREATE', {
        'id': 'ROBOT1.0_msg',
        'author': {'id': 'A', 'member_openid': 'A', 'username': '白轩'},
        'content': 'x',
        'group_openid': 'G',
        'timestamp': '2026-09-27T10:00:00+08:00',
      });

      expect(MessageMapper.attachmentsOf(event), isEmpty);
      expect(MessageMapper.arkOf(event), isNull);
    });
  });

  group('群聊与单聊的场景判定', () {
    test('单聊事件识别为 c2c', () {
      final event = decode('C2C_MESSAGE_CREATE', {
        'id': 'ROBOT1.0_msg',
        'author': {'id': 'U1', 'user_openid': 'U1', 'username': '小明'},
        'content': 'x',
        'timestamp': '2026-09-27T10:00:00+08:00',
      });

      expect(MessageMapper.scopeOf(event), ConversationScope.c2c);
      expect(MessageMapper.conversationOf(event), 'U1');
    });

    test('群全量消息与 @机器人消息都识别为 group', () {
      for (final type in ['GROUP_AT_MESSAGE_CREATE', 'GROUP_MESSAGE_CREATE']) {
        final event = decode(type, {
          'id': 'ROBOT1.0_msg',
          'author': {'id': 'A', 'member_openid': 'A', 'username': '白轩'},
          'content': 'x',
          'group_openid': 'G1',
          'timestamp': '2026-09-27T10:00:00+08:00',
        });

        expect(MessageMapper.scopeOf(event), ConversationScope.group,
            reason: type);
        expect(MessageMapper.conversationOf(event), 'G1', reason: type);
      }
    });
  });
}
