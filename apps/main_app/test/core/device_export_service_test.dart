// Именование файлов при выносе на устройство (#149): выборка ресурсов
// квеста охватывает несколько папок, поэтому в архиве и в выбранной папке
// имена не должны ни терять происхождение, ни затаптывать друг друга.

import 'package:canvas_app/core/services/device_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceExportService.archiveName', () {
    test('виртуальная папка квеста становится каталогом в архиве', () {
      expect(
        DeviceExportService.archiveName(folder: '/Обои', fileName: 'bg.png'),
        'Обои/bg.png',
      );
    });

    test('корень даёт голое имя без ведущего слэша', () {
      expect(
        DeviceExportService.archiveName(folder: '/', fileName: 'bg.png'),
        'bg.png',
      );
    });
  });

  group('DeviceExportService.uniqueNames', () {
    test('одинаковые имена из разных папок получают суффиксы', () {
      expect(
        DeviceExportService.uniqueNames(['1.png', '1.png', '1.png', '2.png']),
        ['1.png', '1 (2).png', '1 (3).png', '2.png'],
      );
    });

    test('расширение остаётся расширением, а не частью имени', () {
      expect(DeviceExportService.uniqueNames(['theme.mp3', 'theme.mp3']), [
        'theme.mp3',
        'theme (2).mp3',
      ]);
    });

    test('файл без точки тоже различим', () {
      expect(DeviceExportService.uniqueNames(['LICENSE', 'LICENSE']), [
        'LICENSE',
        'LICENSE (2)',
      ]);
    });
  });
}
