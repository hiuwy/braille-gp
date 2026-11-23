import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

enum ColorMode { none, protanopia, deuteranopia, tritanopia, inverted, grayscale }

enum DensityOption { standard, comfortable, compact }

enum DirectionOption { auto, ltr, rtl }

class AppSettings extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  set themeMode(ThemeMode value) {
    _themeMode = value;
    notifyListeners();
  }

  double _textScale = 1.0;
  double get textScale => _textScale;
  set textScale(double value) {
    _textScale = value;
    notifyListeners();
  }

  bool _boldText = false;
  bool get boldText => _boldText;
  set boldText(bool value) {
    _boldText = value;
    notifyListeners();
  }

  DirectionOption _direction = DirectionOption.auto;
  DirectionOption get direction => _direction;
  set direction(DirectionOption value) {
    _direction = value;
    notifyListeners();
  }

  TextDirection? get textDirection {
    switch (_direction) {
      case DirectionOption.ltr:
        return TextDirection.ltr;
      case DirectionOption.rtl:
        return TextDirection.rtl;
      case DirectionOption.auto:
        return null;
    }
  }

  DensityOption _density = DensityOption.standard;
  DensityOption get density => _density;
  set density(DensityOption value) {
    _density = value;
    notifyListeners();
  }

  VisualDensity get visualDensity {
    switch (_density) {
      case DensityOption.comfortable:
        return VisualDensity.comfortable;
      case DensityOption.compact:
        return VisualDensity.compact;
      case DensityOption.standard:
        return VisualDensity.standard;
    }
  }

  ColorMode _colorMode = ColorMode.none;
  ColorMode get colorMode => _colorMode;
  set colorMode(ColorMode value) {
    _colorMode = value;
    notifyListeners();
  }

  // Common approximations of colour-vision deficiencies.
  ColorFilter? get colorFilter {
    switch (_colorMode) {
      case ColorMode.none:
        return null;
      case ColorMode.protanopia:
        return const ColorFilter.matrix([
          0.567, 0.433, 0, 0, 0,
          0.558, 0.442, 0, 0, 0,
          0, 0.242, 0.758, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case ColorMode.deuteranopia:
        return const ColorFilter.matrix([
          0.625, 0.375, 0, 0, 0,
          0.7, 0.3, 0, 0, 0,
          0, 0.3, 0.7, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case ColorMode.tritanopia:
        return const ColorFilter.matrix([
          0.95, 0.05, 0, 0, 0,
          0, 0.433, 0.567, 0, 0,
          0, 0.475, 0.525, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case ColorMode.inverted:
        return const ColorFilter.matrix([
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]);
      case ColorMode.grayscale:
        return const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]);
    }
  }

  bool _screenReaderMode = false;
  bool get screenReaderMode => _screenReaderMode;
  set screenReaderMode(bool value) {
    _screenReaderMode = value;
    notifyListeners();
  }
}