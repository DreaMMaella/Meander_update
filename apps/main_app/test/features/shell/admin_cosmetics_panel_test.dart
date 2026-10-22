import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/features/shell/widgets/admin_cosmetics_panel.dart';

/// Бэкенд админки отвечает набором коротких JSON — подменяем их точечно,
/// чтобы видеть, какие вызовы реально делает вкладка «Оформление».
class _FakeApi extends ApiService {
  _FakeApi({this.grantError});

  final Object? grantError;
  final List<String> gets = [];
  final List<Map<String, String>> queries = [];
  final List<String> posts = [];
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    gets.add(endpoint);
    queries.add(queryParams ?? const {});
    if (endpoint == 'admin/cosmetics/users') {
      return {
        'users': [
          {'id': 'u-1', 'full_name': 'Иван Петров', 'avatar_url': null},
          {'id': 'u-2', 'full_name': 'Ирина Сидова', 'avatar_url': null},
        ],
      };
    }
    if (endpoint.startsWith('admin/cosmetics/grants')) {
      return {
        'grants': [
          {
            'user_id': 'u-1',
            'cosmetic_id': 'snowfall',
            'slot': 'effect',
            'tier': 'rare',
            'source': 'admin_grant',
            'reason': 'конкурс',
            'granted_at': '2026-01-10T00:00:00Z',
            'expires_at': null,
          },
        ],
      };
    }
    if (endpoint.startsWith('admin/cosmetics/codes')) {
      return {
        'codes': [
          {
            'code': 'MND-NEWYEAR',
            'cosmetic_ids': ['snowfall'],
            'days_duration': 0,
            'max_uses': 50,
            'current_uses': 3,
            'is_active': true,
            'created_at': '2026-01-10T00:00:00Z',
          },
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    posts.add(endpoint);
    bodies.add(body ?? const {});
    if (endpoint == 'admin/cosmetics/grant' && grantError != null) {
      throw grantError!;
    }
    if (endpoint == 'admin/cosmetics/codes') {
      return {'success': true, 'code': 'MND-TESTCODE'};
    }
    return {'success': true};
  }
}

Future<_FakeApi> _pumpPanel(WidgetTester tester, {Object? grantError}) async {
  final api = _FakeApi(grantError: grantError);
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiServiceProvider.overrideWithValue(api)],
      child: const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: AdminCosmeticsPanel()),
        ),
      ),
    ),
  );
  await _settle(tester);
  return api;
}

/// Коды подгружаются из `microtask`, а SnackBar сидит на таймере 4 с.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _pickTarget(WidgetTester tester, _FakeApi api) async {
  await tester.enterText(find.byType(TextField).first, 'Ива');
  await tester.tap(find.byIcon(Icons.search_rounded));
  await _settle(tester);
  await tester.tap(find.text('Иван Петров'));
  await tester.pump();
}

Future<void> _pickItem(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(InkWell, name));
  await tester.pump();
}

void main() {
  testWidgets('вкладка открывается на каталоге обложек и коды подтянуты', (
    tester,
  ) async {
    final api = await _pumpPanel(tester);

    expect(find.text('КОМУ ВЫДАЁМ'), findsOneWidget);
    expect(find.text('Северное сияние'), findsOneWidget);
    expect(find.text('MND-NEWYEAR'), findsOneWidget);
    expect(api.gets, contains('admin/cosmetics/codes'));
    // Пока никого не выбрали, выдача недоступна.
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Выдать 0 предмет(ов) 0 чел.')).onPressed,
      isNull,
    );
  });

  testWidgets('поиск показывает людей, выбор превращается в чип', (
    tester,
  ) async {
    final api = await _pumpPanel(tester);
    await _pickTarget(tester, api);

    // Запрос уходит в нижнем регистре: бэк сверяет uuid как текст, а в базе
    // он всегда строчный — вставленный ЗАГЛАВНЫМ id иначе не находится.
    expect(api.queries.any((q) => q['q'] == 'ива'), isTrue);
    expect(find.text('Иван Петров'), findsOneWidget);
    expect(find.widgetWithIcon(InputChip, Icons.cancel), findsNothing);
  });

  testWidgets('выдача уходит на сервер списком id и людей', (tester) async {
    final api = await _pumpPanel(tester);
    await _pickTarget(tester, api);
    await _pickItem(tester, 'Северное сияние');
    await _pickItem(tester, 'Поток лавы');

    await tester.tap(
      find.widgetWithText(FilledButton, 'Выдать 2 предмет(ов) 1 чел.'),
    );
    await _settle(tester);

    expect(api.posts, contains('admin/cosmetics/grant'));
    final body = api.bodies.firstWhere((b) => b.containsKey('user_ids'));
    expect(body['user_ids'], ['u-1']);
    expect((body['cosmetic_ids'] as List).toSet(), {'aurora_drift', 'lava_flow'});
    // Пустое поле «дней» = бессрочно: отправлять null незачем.
    expect(body.containsKey('days'), isFalse);
    expect(api.gets, contains('admin/cosmetics/grants'));
    expect(api.queries.any((q) => q['user_id'] == 'u-1'), isTrue);
  });

  testWidgets('ошибка выдачи показывается человекочитаемо', (tester) async {
    final api = await _pumpPanel(
      tester,
      grantError: Exception('Response (400): {"error":"Неизвестные id"}'),
    );
    await _pickTarget(tester, api);
    await _pickItem(tester, 'Северное сияние');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Выдать 1 предмет(ов) 1 чел.'),
    );
    await _settle(tester);

    expect(find.text('Неизвестные id'), findsOneWidget);
  });

  testWidgets('переход на вкладку эффектов и выдача по промокоду', (
    tester,
  ) async {
    final api = await _pumpPanel(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Эффект профиля'));
    await tester.pumpAndSettle();
    expect(find.text('Снегопад'), findsOneWidget);

    await _pickItem(tester, 'Снегопад');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Создать код'));
    await _settle(tester);

    expect(api.posts, contains('admin/cosmetics/codes'));
    expect(
      api.bodies.firstWhere((b) => b.containsKey('max_uses'))['cosmetic_ids'],
      ['snowfall'],
    );
    expect(find.text('MND-TESTCODE'), findsOneWidget);
  });

  testWidgets('фильтр по сезонному выпуску и отметка через вкладки', (
    tester,
  ) async {
    await _pumpPanel(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Эффект профиля'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Новогодний выпуск'));
    await tester.pumpAndSettle();

    expect(find.text('Снегопад'), findsOneWidget);
    expect(find.text('Метель'), findsOneWidget);
    expect(find.text('Денежный дождь'), findsNothing, reason: 'не новогодний эффект');

    await _pickItem(tester, 'Салют');
    expect(find.textContaining('Выдать 1 предмет'), findsOneWidget);

    // Фильтр держится и на другом слоте, и отметка с него не слетает:
    // новогодний набор призёру собираем за один заход.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Рамка аватара'));
    await tester.pumpAndSettle();
    expect(find.text('Иней'), findsOneWidget);
    expect(find.text('Ледяная корона'), findsOneWidget);
    expect(find.text('Призма'), findsNothing);
    expect(find.textContaining('Выдать 1 предмет'), findsOneWidget);

    // Повторный тап по чипу снимает фильтр.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Новогодний выпуск'));
    await tester.pumpAndSettle();
    expect(find.text('Призма'), findsOneWidget);
    expect(find.textContaining('Выдать 1 предмет'), findsOneWidget);
  });

  testWidgets('весь платный каталог отмечается одной кнопкой', (tester) async {
    await _pumpPanel(tester);
    final paid = kCosmetics.where((def) => !def.free).toList();
    final paidBanners = kCosmetics
        .where((def) => !def.free && def.slot == CosmeticSlot.banner)
        .toList();

    // Бесплатное бэкенд не записывает: у таких плиток нет даже кружка выбора.
    expect(find.text('бесплатно · не выдаётся'), findsWidgets);
    expect(
      find.byIcon(Icons.radio_button_unchecked_rounded),
      findsNWidgets(paidBanners.length),
    );

    await tester.tap(find.textContaining('Всё платное сразу'));
    await tester.pump();
    expect(
      find.textContaining('Выдать ${paid.length} предмет'),
      findsOneWidget,
      reason: 'кнопка должна собрать весь каталог, а не одну вкладку',
    );
    // Отмечать больше нечего — остаётся частичное снятие по текущей вкладке.
    expect(find.textContaining('Всё платное'), findsNothing);

    await tester.tap(find.textContaining('Снять показанные'));
    await tester.pump();
    expect(
      find.textContaining('Выдать ${paid.length - paidBanners.length} предмет'),
      findsOneWidget,
      reason: 'снялись только обложки, остальные слоты отмечены',
    );
  });

  testWidgets('список выдач у выбранного человека и отзыв одного предмета', (
    tester,
  ) async {
    final api = await _pumpPanel(tester);
    await _pickTarget(tester, api);
    await tester.tap(find.textContaining('Что уже выдано'));
    await _settle(tester);

    expect(find.text('Снегопад'), findsOneWidget);
    expect(find.textContaining('admin_grant · бессрочно · конкурс'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await _settle(tester);

    final body = api.bodies.firstWhere((b) => b['cosmetic_ids'] != null && b.containsKey('user_id'));
    expect(body['user_id'], 'u-1');
    expect(body['cosmetic_ids'], ['snowfall']);
  });
}
