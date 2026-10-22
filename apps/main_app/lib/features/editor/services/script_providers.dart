import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/features/editor/services/trigger_service.dart';
import 'package:canvas_app/features/editor/services/trigger_validation_service.dart';
import 'package:canvas_app/features/resources/services/resource_providers.dart';

/// Единый маршрутизатор скриптов (открытие редакторов по типу ссылки).
final scriptServiceProvider = Provider.family<ScriptService, String>(
  (ref, questId) =>
      ScriptService(resources: ref.watch(resourceServiceProvider(questId))),
);

/// Единый валидатор onAppear-триггеров для canvas и node-content экранов.
final triggerValidationServiceProvider =
    Provider.family<TriggerValidationService, String>(
  (ref, questId) => TriggerValidationService(questId: questId),
);
