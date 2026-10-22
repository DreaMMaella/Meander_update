// Объединяющий файл: реэкспортирует CSS и склеивает JS-части в единый блок.

import 'quest_html_js_engine.dart';
import 'quest_html_js_runner.dart';
import 'quest_html_js_ui.dart';

export 'quest_html_css.dart' show questHtmlCss;

/// Финальный JS-плеер: склейка движка, ранера и UI обёрнута в IIFE.
final String questHtmlPlayerJs =
    '(function(){"use strict";\n'
    '$questHtmlJsEngine\n'
    '$questHtmlJsRunner\n'
    '$questHtmlJsUi\n'
    '})();';
