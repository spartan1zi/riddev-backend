import 'package:flutter/material.dart';

/// RidDev Worker — same brand family, extra amber accent for “earnings / work”.
class WorkerGradients {
  static const splash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF004D40),
      Color(0xFF00695C),
      Color(0xFF263238),
    ],
  );

  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF00695C),
      Color(0xFF00897B),
      Color(0xFF1565C0),
    ],
  );

  static const earnings = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE65100),
      Color(0xFFF57C00),
      Color(0xFFFFB74D),
    ],
  );
}
