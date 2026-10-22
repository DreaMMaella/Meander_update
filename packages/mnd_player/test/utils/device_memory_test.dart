import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/utils/device_memory.dart';

/// Чтение `hw.memsize` через FFI — единственный способ на iPhone узнать объём
/// памяти без нового плагина в сборке.
void main() {
  group('physicalMemoryBytes', () {
    test('не бросает и не возвращает мусор на платформе без символа', () {
      // Linux/Windows: sysctlbyname в glibc нет, а /proc/meminfo не читаем —
      // обязан вернуться 0, а не кинуть: вызывающий строит на этом решение об
      // отключении эффекта. Android читает /proc/meminfo (там 0 был бы
      // признаком недоступного файла, а не отсутствующего sysctl).
      expect(physicalMemoryBytes() >= 0, isTrue);
      if (!Platform.isMacOS && !Platform.isIOS && !Platform.isAndroid) {
        expect(physicalMemoryBytes(), 0);
      }
    });

    test('на macOS значение реальное', () {
      // На Linux этот кейс скипается; на маке он и есть проверка, что FFI-символ
      // найден и буфер прочитан.
      if (!Platform.isMacOS) {
        markTestSkipped('hw.memsize читается только на Apple-платформах');
        return;
      }
      expect(physicalMemoryBytes(), greaterThan(0));
    });

    test('повторный вызов не течёт и даёт то же число', () {
      final first = physicalMemoryBytes();
      for (var i = 0; i < 50; i++) {
        expect(physicalMemoryBytes(), first);
      }
    });
  });

  group('parseProcMemTotalBytes', () {
    // НЕГАТИВНЫЙ КОНТРОЛЬ (#223): на Android `sysctlbyname` нет, и память
    // устройства определялась как 0 — «неизвестно». Неизвестное раньше считалось
    // поводом размытие запретить, поэтому телефон с 8 ГБ оставался без эффекта.
    // Пустой ответ здесь = «не прочитали», и вызывающий обязан трактовать его
    // как «не резать».
    test('MemTotal из /proc/meminfo — в байтах, с учётом суффикса kB', () {
      expect(
        parseProcMemTotalBytes('MemTotal:        7812340 kB\nMemFree: 1 kB\n'),
        7812340 * 1024,
      );
    });

    test('MemTotal не первый и без суффикса — всё равно находится', () {
      expect(
        parseProcMemTotalBytes('X: 1\nMemTotal: 3906170\nY: 2\n'),
        3906170 * 1024,
      );
    });

    test('нет ключа, не число, ноль — 0, то есть «не определилось»', () {
      expect(parseProcMemTotalBytes(''), 0);
      expect(parseProcMemTotalBytes('MemFree: 12 kB'), 0);
      expect(parseProcMemTotalBytes('MemTotal: abc kB'), 0);
      expect(parseProcMemTotalBytes('MemTotal: 0 kB'), 0);
    });

    test('не путает с MemAvailable и MemTotalAnonSpace (префикс — не совпадение)',
        () {
      expect(
        parseProcMemTotalBytes(
          'MemAvailable:    100 kB\nMemTotal:  200 kB\n',
        ),
        200 * 1024,
      );
    });
  });
}
