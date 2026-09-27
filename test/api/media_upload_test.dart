import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/api/dto/media_payloads.dart';
import 'package:lavedevelop/core/constants/qq_limits.dart';
import 'package:lavedevelop/core/utils/media_checksum.dart';
import 'package:lavedevelop/domain/models/qq_enums.dart';

/// 富媒体上传的解析回归测试。
///
/// 这些用例的字段值来自**真机抓到的实际响应**，不是照着文档编的：
/// 线上曾经因为「把 parts 当字符串数组解析」而每次上传都停在
/// 「响应缺少必要字段」，而响应本身完全正常。文档与实测的差异
/// （index 从 1 开始、block_size 是 number 而非 string）都在这里钉住。
void main() {
  group('upload_prepare 响应解析', () {
    /// 真机响应原文（upload_config 里的重试参数、单分片形态都保留原样）。
    Map<String, dynamic> realSinglePartResponse() => {
          'upload_id': 'upload_1790478803069964609_817217',
          'block_size': 1728171,
          'parts': [
            {
              'index': 1,
              'presigned_url': 'https://qqbot-file-upload-1251316161.cos.'
                  'accelerate.myqcloud.com/robot_upload/102810595/upload_'
                  '1790478803069964609_817217/part_1?x-cos-security-token=***',
              'block_size': 1728171,
            }
          ],
          'upload_config': {
            'concurrency': 1,
            'retry_timeout': 300,
            'retry_delay': 1,
          },
        };

    test('真机响应能被解析成可用状态（曾经的线上故障）', () {
      final prepared = UploadPrepareResponse.fromJson(realSinglePartResponse());

      expect(prepared.isUsable, isTrue);
      expect(prepared.uploadId, 'upload_1790478803069964609_817217');
      expect(prepared.parts, hasLength(1));
      expect(prepared.parts!.first.presignedUrl, contains('/part_1?'));
      expect(prepared.parts!.first.blockSize, 1728171);
      expect(prepared.partUrls, hasLength(1));
    });

    test('parts[].index 原样保留，不按 0 起重排', () {
      // 官方文档写 index 从 0 开始，实测给的是 1。回传时必须是服务端
      // 自己那个值，否则等于告诉服务端「第 0 片好了」而实际传的是别的片。
      final prepared = UploadPrepareResponse.fromJson(realSinglePartResponse());
      expect(prepared.parts!.first.index, 1);
    });

    test('顶层 block_size 是 number 还是 string 都要认', () {
      final asNumber = UploadPrepareResponse.fromJson(
        realSinglePartResponse()..['block_size'] = 1048576,
      );
      final asString = UploadPrepareResponse.fromJson(
        realSinglePartResponse()..['block_size'] = '1048576',
      );
      expect(asNumber.effectiveBlockSize, 1048576);
      expect(asString.effectiveBlockSize, 1048576);
    });

    test('官方示例的多分片形态（index 从 0 起）逐项解析', () {
      final prepared = UploadPrepareResponse.fromJson({
        'upload_id': 'upload_a1b2c3d4e5f6',
        'block_size': '10485760',
        'parts': [
          {'index': 0, 'presigned_url': 'https://cos/1', 'block_size': '10485760'},
          {'index': 1, 'presigned_url': 'https://cos/2', 'block_size': '10485760'},
          {'index': 2, 'presigned_url': 'https://cos/3', 'block_size': '10485760'},
        ],
        'upload_config': {'concurrency': 1, 'retry_timeout': 300, 'retry_delay': 1},
      });

      expect(prepared.parts, hasLength(3));
      expect(prepared.parts!.map((e) => e.index), [0, 1, 2]);
      expect(prepared.parts!.map((e) => e.presignedUrl), [
        'https://cos/1',
        'https://cos/2',
        'https://cos/3',
      ]);
      expect(prepared.effectiveBlockSize, 10485760);
    });

    test('缺少 presigned_url 的分片被丢弃，而不是留成空地址', () {
      final prepared = UploadPrepareResponse.fromJson({
        'upload_id': 'u',
        'parts': [
          {'index': 0, 'block_size': 10},
          {'index': 1, 'presigned_url': 'https://cos/2'},
        ],
      });
      expect(prepared.parts, hasLength(1));
      expect(prepared.parts!.first.index, 1);
    });

    test('分片地址退化成字符串数组时仍可用', () {
      final prepared = UploadPrepareResponse.fromJson({
        'upload_id': 'u',
        'block_size': '100',
        'parts': ['https://cos/a', 'https://cos/b'],
      });
      expect(prepared.isUsable, isTrue);
      expect(prepared.parts!.map((e) => e.presignedUrl), [
        'https://cos/a',
        'https://cos/b',
      ]);
      // 字符串形态没有自带大小，解析时用顶层值兜底，
      // 这样分片切分仍然有依据，而不是退回到 5MB 默认值。
      expect(prepared.parts!.first.blockSize, 100);
      expect(prepared.effectiveBlockSize, 100);
    });

    test('没有 upload_id 时不认为可用', () {
      final prepared = UploadPrepareResponse.fromJson({
        'parts': [
          {'index': 0, 'presigned_url': 'https://cos/a'},
        ],
      });
      expect(prepared.isUsable, isFalse);
    });

    test('upload_config 缺省时回落到官方默认值', () {
      final prepared = UploadPrepareResponse.fromJson({'upload_id': 'u'});
      expect(prepared.uploadConfig, isNull);
      // 调用点用的是这个默认实例。
      const fallback = UploadConfig();
      expect(fallback.concurrency, 1);
      expect(fallback.retryTimeout, 300);
      expect(fallback.retryDelayDuration, const Duration(seconds: 1));
    });
  });

  group('upload_prepare 请求体', () {
    test('三个校验值都按官方字段名发出，file_size 是字符串', () {
      final json = UploadPrepareRequest(
        fileType: QqMediaFileType.image,
        fileSize: 605516,
        fileName: 'a.png',
        md5: 'm',
        sha1: 's',
        md5Prefix: 'm10',
      ).toJson();

      expect(json['file_type'], 1);
      expect(json['file_size'], '605516');
      expect(json['file_name'], 'a.png');
      expect(json['md5'], 'm');
      expect(json['sha1'], 's');
      expect(json['md5_10m'], 'm10');
    });
  });

  group('upload_part_finish 请求体', () {
    test('字段名是 part_index 而不是 part_number', () {
      // 曾把这里写成 part_number，服务端收不到分片序号且不报错，
      // 上传会「成功」但合并后拿不到有效文件。
      final json = UploadPartFinishRequest(
        uploadId: 'upload_x',
        partIndex: 1,
        blockSize: 1728171,
        md5: 'abc',
      ).toJson();

      expect(json.keys.toSet(), {'upload_id', 'part_index', 'block_size', 'md5'});
      expect(json['upload_id'], 'upload_x');
      expect(json['part_index'], 1);
      expect(json['block_size'], '1728171');
      expect(json['md5'], 'abc');
      expect(json.containsKey('part_number'), isFalse);
    });
  });

  group('MediaChecksum', () {
    test('md5 / sha1 与已知向量一致', () {
      // 空串的 MD5 与 SHA1 是最常被引用的两个标准向量。
      expect(MediaChecksum.md5Of(const []),
          'd41d8cd98f00b204e9800998ecf8427e');
      expect(MediaChecksum.sha1Of(const []),
          'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(MediaChecksum.md5Of(utf8.encode('abc')),
          '900150983cd24fb0d6963f7d28e17f72');
    });

    test('文件短于取样长度时 md5_10m 等于整文件 MD5', () {
      final bytes = Uint8List.fromList(utf8.encode('hello rich media'));
      final checksum = MediaChecksum.of(bytes);
      expect(checksum.md5Prefix, checksum.md5);
    });

    test('文件长于取样长度时只取前 10002432 字节', () {
      // 取样长度是 10002432（官方原文），不是 10MiB = 10485760。
      expect(QqLimits.md5PrefixBytes, 10002432);

      final bytes = Uint8List(QqLimits.md5PrefixBytes + 4096);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i % 251;
      }
      final checksum = MediaChecksum.of(bytes);
      final expectedPrefix =
          MediaChecksum.md5Of(Uint8List.sublistView(bytes, 0, QqLimits.md5PrefixBytes));

      expect(checksum.md5Prefix, expectedPrefix);
      expect(checksum.md5Prefix, isNot(checksum.md5));
    });

    test('toString 只暴露摘要前 8 位', () {
      final checksum = MediaChecksum.of(Uint8List.fromList([1, 2, 3]));
      expect(checksum.toString(), contains('…'));
      expect(checksum.toString().length, lessThan(60));
    });
  });
}
