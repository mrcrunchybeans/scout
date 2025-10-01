import 'package:flutter/material.dart';

Widget testStructure() {
  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 1,
    child: Container(
      decoration: null,
      child: Opacity(
        opacity: 1.0,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('test'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}