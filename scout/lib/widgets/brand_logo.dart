// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  final double height;
  const BrandLogo({super.key, this.height = 300});

  @override
  Widget build(BuildContext context) {
    // Access the current theme's brightness
    final brightness = Theme.of(context).brightness;

    // Choose logo based on theme - PNG as primary
    // Flutter automatically uses @2x, @3x variants for high-DPI displays
    final logoPath = brightness == Brightness.dark
        ? 'assets/images/scout dash logo dark mode.png'
        : 'assets/images/scout dash logo light mode.png';

    return Container(
      height: height,
      constraints: BoxConstraints(
        maxWidth: height * 2, // Assume reasonable aspect ratio, adjust as needed
      ),
      child: Image.asset(
        logoPath,
        height: height,
        fit: BoxFit.contain, // Maintain aspect ratio and fit within bounds
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to text logo if PNG fails to load
          return Container(
            height: height,
            alignment: Alignment.center,
            child: Text(
              'SCOUT',
              style: TextStyle(
                fontSize: height * 0.2, // Scale font size with height
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        },
      ),
    );
  }
}