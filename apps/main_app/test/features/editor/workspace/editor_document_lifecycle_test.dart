import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/editor/workspace/editor_document.dart';
import 'package:canvas_app/features/editor/workspace/editor_document_lifecycle.dart';
import 'package:canvas_app/features/editor/workspace/editor_workspace_controller.dart';

void main() {
  test('EditorDocumentHandle forwards calls while valid', () {
    final marks = <(String, bool)>[];
    final registered = <String>[];
    final unregistered = <String>[];

    final handle = EditorDocumentHandle(
      id: EditorDocumentId(
        questId: 'q1',
        kind: EditorDocumentKind.canvas,
        key: 'k',
      ),
      markDirty: (id, dirty) => marks.add((id.key, dirty)),
      registerRuntime: (id, _) => registered.add(id.key),
      unregisterRuntime: (id) => unregistered.add(id.key),
    );

    handle.markDirty(true);
    handle.registerRuntime(const EditorDocumentRuntime());
    handle.unregisterRuntime();

    expect(marks, [('k', true)]);
    expect(registered, ['k']);
    expect(unregistered, ['k']);
  });

  test('EditorDocumentHandle is a no-op after invalidation and swallows errors',
      () {
    var throwsOnMark = true;
    final handle = EditorDocumentHandle(
      id: EditorDocumentId(
        questId: 'q1',
        kind: EditorDocumentKind.canvas,
        key: 'k',
      ),
      markDirty: (id, dirty) {
        if (throwsOnMark) {
          throw StateError('workspace controller is dead');
        }
      },
      registerRuntime: (_, _) {},
      unregisterRuntime: (_) {},
    );

    // Вызов на «мёртвом» воркспейсе не должен бросать.
    expect(() => handle.markDirty(true), returnsNormally);

    handle.invalidated = true;
    throwsOnMark = false;

    handle.markDirty(false);
    handle.registerRuntime(const EditorDocumentRuntime());
    handle.unregisterRuntime();
    // Никаких исключений и никаких вызовов — просто no-op.
  });
}
