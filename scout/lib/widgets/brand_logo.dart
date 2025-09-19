// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  final double height;
  const BrandLogo({super.key, this.height = 300});

  @override
  Widget build(BuildContext context) {
    // Access the current theme's color scheme
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset('assets/images/scout_logo.png', height: height),
        const SizedBox(height: 8),
        Text(
          'S.C.O.U.T.',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Spiritual Care Operations & Usage Tracker',
          style: textTheme.titleSmall?.copyWith(
            color: colorScheme.onBackground.withValues(alpha: 0.7),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}