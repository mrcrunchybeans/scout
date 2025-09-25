import 'package:flutter/material.dart';

/// A simple 3 × 10 grid preview for Avery 5160 sheets (30 labels).
/// - [selectedIndex] is 0-based (0..29).
/// - [onSelected] is called with the new 0-based index when a cell is tapped.
/// - Optionally pass [disabledIndices] to gray out certain positions.
class LabelSheetPreview extends StatelessWidget {
  final int selectedIndex; // 0..29
  final ValueChanged<int>? onSelected;
  final Set<int> disabledIndices;

  const LabelSheetPreview({
    super.key,
    required this.selectedIndex,
    this.onSelected,
    this.disabledIndices = const {},
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AspectRatio(
      aspectRatio: 8.5 / 11.0, // Rough page shape, looks nice in dialog
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: GridView.builder(
          itemCount: 30,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, // 3 columns × 10 rows
          ),
          itemBuilder: (context, i) {
            final oneBased = i + 1;
            final isSelected = i == selectedIndex;
            final isDisabled = disabledIndices.contains(i);

            Color bg;
            Color border;
            Color txt;

            if (isDisabled) {
              bg = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
              border = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
              txt = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
            } else if (isSelected) {
              bg = theme.colorScheme.primary.withValues(alpha:0.18);
              border = theme.colorScheme.primary;
              txt = theme.colorScheme.primary;
            } else {
              bg = isDark ? Colors.black : Colors.white;
              border = theme.dividerColor.withValues(alpha:0.6);
              txt = isDark ? Colors.white70 : Colors.black87;
            }

            return InkWell(
              onTap: isDisabled || onSelected == null ? null : () => onSelected!(i),
              child: Container(
                decoration: BoxDecoration(
                  color: bg,
                  border: Border(
                    top: BorderSide(color: border, width: 0.6),
                    right: BorderSide(color: border, width: (i % 3 == 2) ? 0.6 : 0.3),
                    left: BorderSide(color: border, width: (i % 3 == 0) ? 0.6 : 0.3),
                    bottom: BorderSide(color: border, width: (i ~/ 3 == 9) ? 0.6 : 0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Label $oneBased',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: txt,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
