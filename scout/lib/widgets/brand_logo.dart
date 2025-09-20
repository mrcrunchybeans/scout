// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  final double height;
  const BrandLogo({super.key, this.height = 300});

  @override
  Widget build(BuildContext context) {
    // Access the current theme's brightness
    final brightness = Theme.of(context).brightness;
    
    // Choose logo based on theme
    final logoPath = brightness == Brightness.light
        ? 'assets/images/scout dash logo dark mode.png'
        : 'assets/images/scout dash logo light mode.png';

    return Image.asset(logoPath, height: height);
  }
}