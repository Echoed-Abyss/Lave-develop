import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/core/utils/qq_avatar.dart';
import 'package:lavedevelop/domain/models/bot_profile.dart';
import 'package:lavedevelop/domain/models/qq_enums.dart';
import 'package:lavedevelop/domain/models/qq_message.dart';
import 'package:lavedevelop/gateway/protocol/models/qq_user.dart';

void main() {
  group('BotProfile 展示名', () {
    test('优先级：用户备注名 → 官方昵称 → AppID', () {
      const withRemark = BotProfile(
        appId: '102810595',
        displayName: '我的机器人',
        officialName: '落日余晖',
      );
      expect(withRemark.title, '我的机器人');

      const withoutRemark = BotProfile(
        appId: '102810595',
        displayName: '',
        officialName: '落日余晖',
      );
      expect(withoutRemark.title, '落日余晖');

      const bare = BotProfile(appId: '102810595', displayName: '');
      expect(bare.title, '102810595');
    });

    test('官方昵称为空白时也回退到 AppID', () {
      const bot = BotProfile(
        appId: '102810595',
        displayName: '',
        officialName: '   ',
      );
      expect(bot.title, '102810595');
    });

    test('序列化能带上官方昵称与头像', () {
      const bot = BotProfile(
        appId: '102810595',
        displayName: '',
        officialName: '落日余晖',
        avatarUrl: 'https://thirdqq.qlogo.cn/g?b=oidb&k=abc&s=0',
      );

      final restored = BotProfile.fromJson(bot.toJson());
      expect(restored.officialName, '落日余晖');
      expect(restored.avatarUrl, 'https://thirdqq.qlogo.cn/g?b=oidb&k=abc&s=0');
      expect(restored.title, '落日余晖');
    });

    test('copyWith 不会把官方昵称写丢', () {
      const bot = BotProfile(
        appId: '1',
        displayName: '备注',
        officialName: '官方名',
      );
      // 资料刷新走的是 updateIdentity，它基于 copyWith；
      // 若 copyWith 漏字段，用户的官方昵称与头像会在第一次编辑后消失。
      expect(bot.copyWith(displayName: '新备注').officialName, '官方名');
    });
  });

  group('QqAvatar 头像地址构造', () {
    test('按 AppID + openid 拼出头像地址，默认 100 档', () {
      final url = QqAvatar.forOpenid(
        appId: '102810595',
        openid: 'CA87605D7C22D7BA4863B86754D1876D',
      );
      expect(
        url,
        'https://q.qlogo.cn/qqapp/102810595/'
        'CA87605D7C22D7BA4863B86754D1876D/100',
      );
    });

    test('尺寸档位可覆盖（CDN 实测支持 40 / 100 / 640 / 0）', () {
      String? at(int size) => QqAvatar.forOpenid(
            appId: '1',
            openid: 'AB',
            size: size,
          );
      expect(at(QqAvatar.small), endsWith('/40'));
      expect(at(QqAvatar.large), endsWith('/640'));
      expect(at(QqAvatar.original), endsWith('/0'));
    });

    test('缺少 AppID 或 openid 时返回 null，而不是拼出一个无效地址', () {
      // 拼出来必然只会拿到 CDN 的默认灰头像，不如让界面用可区分的占位。
      expect(QqAvatar.forOpenid(appId: null, openid: 'AB'), isNull);
      expect(QqAvatar.forOpenid(appId: '', openid: 'AB'), isNull);
      expect(QqAvatar.forOpenid(appId: '1', openid: null), isNull);
      expect(QqAvatar.forOpenid(appId: '1', openid: '   '), isNull);
    });

    test('两端空白被裁掉，特殊字符被编码', () {
      expect(
        QqAvatar.forOpenid(appId: ' 1 ', openid: ' AB '),
        'https://q.qlogo.cn/qqapp/1/AB/100',
      );
      // openid 目前是十六进制串，编码只是防御性写法：
      // 官方一旦换成含特殊字符的形态，拼串会静默错误。
      expect(
        QqAvatar.forOpenid(appId: '1', openid: 'a/b'),
        contains('a%2Fb'),
      );
    });
  });

  group('头像字段解析', () {
    test('QqUser 解析 avatar', () {
      final user = QqUser.fromJson({
        'id': 'A1B2',
        'username': '白轩',
        'avatar': 'https://thirdqq.qlogo.cn/g?b=oidb&k=x&s=0',
      });
      expect(user.avatar, 'https://thirdqq.qlogo.cn/g?b=oidb&k=x&s=0');
      expect(user.username, '白轩');
    });

    test('官方示例里没有 avatar 时为 null（单聊/群聊事件的真实情况）', () {
      // 官方对 C2C_MESSAGE_CREATE / GROUP_AT_MESSAGE_CREATE 的 User 表里
      // 并没有 avatar 字段，因此这里必须是 null 而不是空串——
      // 界面据此退回确定性占位。
      final user = QqUser.fromJson({
        'id': 'A1B2',
        'member_openid': 'A1B2',
        'member_role': 'member',
        'username': '小明',
      });
      expect(user.avatar, isNull);
    });

    test('空字符串的 avatar 归一为 null', () {
      final user = QqUser.fromJson({'id': 'x', 'avatar': ''});
      expect(user.avatar, isNull);
    });

    test('ActorRef 默认没有头像', () {
      const ref = ActorRef(scopeId: 'A1B2', displayName: '小明');
      expect(ref.avatarUrl, isNull);
      expect(ref.label, '小明');
    });

    test('没有昵称时用 openid 尾部兜底（占位首字不会空白）', () {
      const ref = ActorRef(scopeId: 'ABCDEF123456');
      expect(ref.label, '用户…123456');
    });
  });

  group('消息携带发送者头像', () {
    test('入站消息的头像来自事件 author.avatar（有则带上）', () {
      final message = QqMessage(
        localId: 1,
        botId: '1',
        scope: ConversationScope.group,
        conversationId: 'group',
        sender: const ActorRef(
          scopeId: 'member',
          displayName: '小明',
          avatarUrl: 'https://example.com/a.png',
        ),
        direction: MessageDirection.incoming,
        at: DateTime(2026, 9, 27),
      );

      expect(message.sender.avatarUrl, 'https://example.com/a.png');
    });
  });
}
