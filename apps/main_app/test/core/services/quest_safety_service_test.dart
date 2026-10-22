import 'package:canvas_app/core/services/quest_safety_service.dart';
import 'package:mnd_core/models/quest_descriptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuestNetworkSafety', () {
    test('allows regular HTTP and HTTPS URLs', () {
      expect(
        QuestNetworkSafety.checkUrl('https://example.com/path').allowed,
        isTrue,
      );
      expect(
        QuestNetworkSafety.checkUrl('http://api.example.com:8080').allowed,
        isTrue,
      );
    });

    test('blocks dangerous schemes, credentials and missing hosts', () {
      for (final url in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'https://user:password@example.com',
        'https://',
      ]) {
        expect(
          QuestNetworkSafety.checkUrl(url).allowed,
          isFalse,
          reason: 'must block $url',
        );
      }
    });

    test('blocks local, reserved and metadata addresses', () {
      for (final url in [
        'http://localhost:8080',
        'http://localhost.',
        'http://127.0.0.1',
        'http://192.168.1.20',
        'http://169.254.169.254/latest/meta-data',
        'http://[::1]',
        'http://[fc00::1]',
        'http://metadata.google.internal',
      ]) {
        expect(
          QuestNetworkSafety.checkUrl(url).allowed,
          isFalse,
          reason: 'must block $url',
        );
      }
    });

    test('blocks known tracking and request-capture hosts', () {
      for (final url in [
        'https://example.iplogger.org/click',
        'https://grabify.link/abc',
        'https://webhook.site/token',
        'https://collector.oast.example/hit',
      ]) {
        expect(
          QuestNetworkSafety.checkUrl(url).allowed,
          isFalse,
          reason: 'must block $url',
        );
      }
    });
  });

  group('Quest metadata', () {
    test('reads and serializes the persistent last edit timestamp', () {
      final quest = Quest.fromJson({
        'id': 'q1',
        'title': 'Quest',
        'updated': '2025-11-20T12:00:00.000Z',
      });

      expect(quest.lastEditedAt, DateTime.parse('2025-11-20T12:00:00.000Z'));
      expect(quest.toJson()['lastEditedAt'], '2025-11-20T12:00:00.000Z');
    });
  });

  group('QuestSafetyReport', () {
    test('warns even when the author is verified', () {
      const report = QuestSafetyReport(
        internetBlockCount: 1,
        blockedUrlCount: 1,
        authorIsVerified: true,
      );

      expect(report.shouldWarnAboutInternet, isTrue);
      expect(report.shouldShowWarning, isTrue);
    });

    test('does not warn for a fresh offline quest without network blocks', () {
      final report = QuestSafetyReport(
        lastEditedAt: DateTime(2026, 8, 20),
        questVersion: '1.0.0',
      );

      expect(report.shouldWarnAboutInternet, isFalse);
      expect(report.shouldShowWarning, isFalse);
    });

    test('warns about a stale quest', () {
      final report = QuestSafetyReport(
        lastEditedAt: DateTime.now().toUtc().subtract(const Duration(days: 181)),
      );

      expect(report.isStale, isTrue);
      expect(report.shouldShowWarning, isTrue);
    });
  });
}
