import 'package:canvas_app/features/profile/screens/avatar_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Математика кадрирования — единственная часть экрана аватара, которую можно
/// проверить без живого файла и без сети: на входе размеры и матрица, на
/// выходе квадрат пикселей исходника.
void main() {
  // Картинка 200×100 при cover-подгонке под квадрат 300 рисуется 600×300.
  const wide = Size(200, 100);
  const wideBase = Size(600, 300);

  Matrix4 centered(Size base) => Matrix4.identity()
    ..translate(
      -(base.width - kAvatarCropSide) / 2,
      -(base.height - kAvatarCropSide) / 2,
    );

  test('квадратная картинка режется целиком', () {
    final rect = AvatarEditorScreen.cropSourceRect(
      imageSize: const Size(100, 100),
      baseSize: const Size(300, 300),
      transform: Matrix4.identity(),
      side: kAvatarCropSide,
    );
    expect(rect, const Rect.fromLTRB(0, 0, 100, 100));
  });

  test('широкая картинка: в аватар попадает середина по горизонтали', () {
    final rect = AvatarEditorScreen.cropSourceRect(
      imageSize: wide,
      baseSize: wideBase,
      transform: centered(wideBase),
      side: kAvatarCropSide,
    );
    // Из 200 px ширины видимые — средние 100 px (50..150), высота вся.
    expect(rect, const Rect.fromLTRB(50, 0, 150, 100));
  });

  test('высокая картинка: в аватар попадает середина по вертикали', () {
    final base = const Size(300, 600);
    final rect = AvatarEditorScreen.cropSourceRect(
      imageSize: const Size(100, 200),
      baseSize: base,
      transform: centered(base),
      side: kAvatarCropSide,
    );
    expect(rect, const Rect.fromLTRB(0, 50, 100, 150));
  });

  test('зум берёт из исходника ровно столько, сколько видно', () {
    // 2× поверх той же картинки: кадр 600×300 → 1200×600, по центру.
    final transform = Matrix4.identity()
      ..translate(
        -(wideBase.width * 2 - kAvatarCropSide) / 2,
        -(wideBase.height * 2 - kAvatarCropSide) / 2,
      )
      ..scale(2.0);
    final rect = AvatarEditorScreen.cropSourceRect(
      imageSize: wide,
      baseSize: wideBase,
      transform: transform,
      side: kAvatarCropSide,
    );
    // Приближение в два раза = в кадр попадает половина ширины исходника
    // (50 из 200) и половина высоты по центру.
    expect(rect, const Rect.fromLTRB(75, 25, 125, 75));
  });

  test('сдвиг за край не даёт кадра вместо битого аватара', () {
    final transform = Matrix4.identity()..translate(400.0, 0.0);
    expect(
      AvatarEditorScreen.cropSourceRect(
        imageSize: wide,
        baseSize: wideBase,
        transform: transform,
        side: kAvatarCropSide,
      ),
      isNull,
    );
  });
}
