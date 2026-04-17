import 'package:flutter/material.dart';

import '../core/config.dart';

/// Stand-in for Google Maps (no native SDK — avoids API-key crashes).
class MapPlaceholder extends StatelessWidget {
  const MapPlaceholder({super.key, this.hint});

  final String? hint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHighest,
            cs.surfaceContainer,
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on_rounded, size: 56, color: cs.primary),
              const SizedBox(height: 12),
              Text(
                'Location',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '${kAccraLat.toStringAsFixed(4)}, ${kAccraLng.toStringAsFixed(4)} · Accra area',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              if (hint != null) ...[
                const SizedBox(height: 10),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.outline, fontSize: 12, height: 1.35),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
