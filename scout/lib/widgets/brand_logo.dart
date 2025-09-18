import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  final double height;
  const BrandLogo({super.key, this.height = 300});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset('../assets/images/scout_logo.png', height: height),
        const SizedBox(height: 8),
        Text(
          'S.C.O.U.T.',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color.fromARGB(255, 36, 36, 36),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
        ),
                const SizedBox(height: 8),
        Text(
          'Spiritual Care Operations & Usage Tracker',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: const Color.fromARGB(255, 36, 36, 36),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
        ),
      ],
    );
  }
}
