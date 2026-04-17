import 'package:flutter/material.dart';

class AppGradients {
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0D47A1),
      Color(0xFF1565C0),
      Color(0xFF00838F),
    ],
  );

  static const splash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0D47A1),
      Color(0xFF1565C0),
      Color(0xFF263238),
    ],
  );

  static const cardSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE3F2FD),
      Color(0xFFE0F7FA),
    ],
  );
}
