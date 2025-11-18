# scout

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Items page URL parameters

You can share filtered/sorted links to the Items page. Supported query params:

- q: text search query
- low: 1 to filter low stock
- lots: 1 to require items with lots
- barcode: 1 to require items with barcode(s)
- minQty: 1 to show items with a minimum quantity set
- expSoon: 1 to show expiring soon
- stale: 1 to show stale items
- excess: 1 to show excess items
- expired: 1 to show expired
- cats: comma-separated categories, e.g. `Food,Clothing`
- locs: comma-separated location IDs
- sort: one of `recent`, `name-asc`, `name-desc`, `cat-asc`, `cat-desc`, `qty-asc`, `qty-desc`, `exp-asc`, `exp-desc`
- archived: 1 to show archived items
- bucket: quick presets used by dashboard links: `low`, `expiring`, `stale`, `expired`

Examples:

- Recent items with low stock: `/items?low=1&sort=recent`
- Expiring soon in Food category: `/items?expSoon=1&cats=Food`
- Archived items sorted by name: `/items?archived=1&sort=name-asc`
