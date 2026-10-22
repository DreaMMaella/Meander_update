import 'dart:math' as math;

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:mnd_player/widgets/shared/module_asset_frame.dart';
import 'package:flutter/material.dart';

class ButtonModulePreviewScreen extends StatefulWidget {
  final String questId;
  final ButtonStyleConfig style;
  final String? title;
  final List<String> sampleTexts;

  const ButtonModulePreviewScreen({
    super.key,
    required this.questId,
    required this.style,
    this.title,
    this.sampleTexts = const [],
  });

  @override
  State<ButtonModulePreviewScreen> createState() =>
      _ButtonModulePreviewScreenState();
}

class _ButtonModulePreviewScreenState extends State<ButtonModulePreviewScreen> {
  final TransformationController _controller = TransformationController();

  int _textIndex = 0;
  bool _showGrid = true;
  bool _showTiles = true;
  bool _showText = true;
  double _scale = 1.0;
  bool _autoFit = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setScale(double value, {bool userAction = true}) {
    if (userAction) _autoFit = false;
    final clamped = value.clamp(0.5, 8.0);
    setState(() => _scale = clamped);
    _controller.value = Matrix4.identity()..scale(_scale);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final texts = widget.sampleTexts.isNotEmpty
        ? widget.sampleTexts
        : [
            tr('ПРИМЕР ТЕКСТА'),
            tr('Вы можете собрать Василию:\n- Я не видел Олега сегодня'),
          ];
    final safeTextIndex = math.min(_textIndex, texts.length - 1);
    final currentText = texts[safeTextIndex];
    final module = style.moduleSize.clamp(6.0, 32.0);
    final horizontalPadding = (module * 0.6).clamp(10.0, 80.0);
    final verticalPadding = (module * 0.4).clamp(8.0, 34.0);
    final maxTotalWidth =
        (MediaQuery.of(context).size.width * 0.9).clamp(240.0, 900.0);
    final maxCenterModules =
        ((maxTotalWidth / module).floor() - 2).clamp(1, 40);
    int widthModules = style.horizontalModules.clamp(2, 40);
    int verticalModules = style.verticalModules.clamp(2, 20);
    if (style.autoCenterByText) {
      final painter = TextPainter(
        text: TextSpan(
          text: currentText,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      final maxTextWidth =
          (maxTotalWidth - 2 * horizontalPadding).clamp(40.0, maxTotalWidth);
      painter.layout(maxWidth: maxTextWidth);
      final contentWidth = painter.width + (2 * horizontalPadding);
      final contentHeight = painter.height + (2 * verticalPadding);
      widthModules = (contentWidth / module)
          .ceil()
          .clamp(style.horizontalModules, maxCenterModules);
      final lineCount = painter.computeLineMetrics().length;
      final rawHeightModules = (contentHeight / module).ceil().clamp(1, 20);
      if (lineCount <= 1) {
        verticalModules = rawHeightModules.clamp(1, widthModules);
      } else {
        verticalModules = rawHeightModules;
      }
    }
    final width = module * (widthModules + 2);
    final height = module * (verticalModules + 2);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: Text(widget.title ?? tr('Превью компоновки')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<int>(
                      value: safeTextIndex,
                      dropdownColor: const Color(0xFF2A2A2A),
                      style: const TextStyle(color: Colors.white),
                      iconEnabledColor: Colors.white70,
                      items: List.generate(
                        texts.length,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text(trf('Текст {p0}', {'p0': i + 1})),
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _textIndex = value);
                      },
                    ),
                    FilterChip(
                      label: Text(tr('Сетка')),
                      selected: _showGrid,
                      selectedColor: const Color(0xFF00C853),
                      checkmarkColor: Colors.black,
                      backgroundColor: const Color(0xFF1E1E1E),
                      labelStyle: const TextStyle(color: Colors.white),
                      onSelected: (v) => setState(() => _showGrid = v),
                    ),
                    FilterChip(
                      label: Text(tr('Границы тайлов')),
                      selected: _showTiles,
                      selectedColor: const Color(0xFF00C853),
                      checkmarkColor: Colors.black,
                      backgroundColor: const Color(0xFF1E1E1E),
                      labelStyle: const TextStyle(color: Colors.white),
                      onSelected: (v) => setState(() => _showTiles = v),
                    ),
                    FilterChip(
                      label: Text(tr('Текст')),
                      selected: _showText,
                      selectedColor: const Color(0xFF00C853),
                      checkmarkColor: Colors.black,
                      backgroundColor: const Color(0xFF1E1E1E),
                      labelStyle: const TextStyle(color: Colors.white),
                      onSelected: (v) => setState(() => _showText = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      tr('Зум'),
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: _scale,
                        min: 0.5,
                        max: 8.0,
                        onChanged: (v) => _setScale(v),
                      ),
                    ),
                    Text(
                      '${_scale.toStringAsFixed(2)}x',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _setScale(1.0),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Text(tr('Сброс')),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  trf('Размер: {p0}x{p1} px, модуль: {p2} px', {'p0': width.toStringAsFixed(0), 'p1': height.toStringAsFixed(0), 'p2': module.toStringAsFixed(0)}),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_autoFit) {
                  final rawScale = math.min(
                    (constraints.maxWidth * 0.9) / width,
                    (constraints.maxHeight * 0.9) / height,
                  );
                  final minPixelScale = math.max(320 / width, 220 / height);
                  final fitScale = math
                      .max(rawScale, math.max(minPixelScale, 2.5))
                      .clamp(0.5, 8.0);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _autoFit) {
                      _autoFit = false;
                      _setScale(fitScale, userAction: false);
                    }
                  });
                }
                return Center(
                  child: InteractiveViewer(
                    transformationController: _controller,
                    minScale: 0.5,
                    maxScale: 8.0,
                    child: Container(
                      width: width,
                      height: height,
                      color: const Color(0xFF1A1A1A),
                      child: Stack(
                        children: [
                          if (style.hasModuleAssets)
                            ModuleAssetLayer(
                              questId: widget.questId,
                              style: style,
                              module: module,
                              fallbackColor: style.fillColor.withOpacity(0.92),
                            )
                          else
                            Center(
                              child: Text(
                                tr('Выберите все 4 модуля пресета'),
                                style: TextStyle(color: Colors.white60),
                              ),
                            ),
                          CustomPaint(
                            painter: _ModuleDebugPainter(
                              module: module,
                              centerModules: widthModules,
                              verticalModules: verticalModules,
                              showGrid: _showGrid,
                              showTiles: _showTiles,
                            ),
                            size: Size(width, height),
                          ),
                          if (_showText)
                            Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: module * 1.2,
                                  vertical: module * 0.9,
                                ),
                                child: Text(
                                  currentText,
                                  textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                height: 1.2,
                              ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleDebugPainter extends CustomPainter {
  final double module;
  final int centerModules;
  final int verticalModules;
  final bool showGrid;
  final bool showTiles;

  _ModuleDebugPainter({
    required this.module,
    required this.centerModules,
    required this.verticalModules,
    required this.showGrid,
    required this.showTiles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withOpacity(0.12)
        ..strokeWidth = 1;
      for (double x = 0; x <= size.width; x += module) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y <= size.height; y += module) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    if (showTiles) {
      final edge = module;
      final tilePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      tilePaint.color = Colors.orange.withOpacity(0.7);
      canvas.drawRect(Rect.fromLTWH(0, 0, module, module), tilePaint);
      canvas.drawRect(
        Rect.fromLTWH(size.width - module, 0, module, module),
        tilePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - module, module, module),
        tilePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          size.width - module,
          size.height - module,
          module,
          module,
        ),
        tilePaint,
      );

      tilePaint.color = Colors.greenAccent.withOpacity(0.7);
      canvas.drawRect(
        Rect.fromLTWH(edge, 0, size.width - edge * 2, module),
        tilePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          edge,
          size.height - module,
          size.width - edge * 2,
          module,
        ),
        tilePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, edge, module, size.height - edge * 2),
        tilePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          size.width - module,
          edge,
          module,
          size.height - edge * 2,
        ),
        tilePaint,
      );

      tilePaint.color = Colors.lightBlueAccent.withOpacity(0.7);
      canvas.drawRect(
        Rect.fromLTWH(edge, edge, size.width - edge * 2, size.height - edge * 2),
        tilePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ModuleDebugPainter oldDelegate) {
    return oldDelegate.showGrid != showGrid ||
        oldDelegate.showTiles != showTiles ||
        oldDelegate.module != module ||
        oldDelegate.centerModules != centerModules ||
        oldDelegate.verticalModules != verticalModules;
  }
}
