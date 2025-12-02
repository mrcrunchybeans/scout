import 'package:flutter/material.dart';
import 'budget_page.dart';

class BudgetNavTile extends StatelessWidget {
  const BudgetNavTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.account_balance_wallet),
      title: const Text('Team Budget'),
      subtitle: const Text('Collaborative budget management'),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BudgetPage()),
        );
      },
    );
  }
}
