import json
from itertools import product

OUTPUT_PATH = r"c:\\Users\\Brian\\scout\\scout\\scout\\firestore.indexes.json"

indexes = []
seen = set()


def add(fields, collection_group="items"):
    fields = tuple(fields)
    key = (collection_group, fields)
    if key in seen:
        return
    seen.add(key)
    indexes.append(
        {
            "collectionGroup": collection_group,
            "queryScope": "COLLECTION",
            "fields": [{"fieldPath": field, "order": order} for field, order in fields],
        }
    )


common_sorts = [
    ("updatedAt", "DESCENDING"),
    ("name", "ASCENDING"),
    ("name", "DESCENDING"),
    ("qtyOnHand", "ASCENDING"),
    ("qtyOnHand", "DESCENDING"),
]


def add_filter_indexes(base_fields, include_category_sort=True):
    base_fields = tuple(sorted(base_fields))
    eq_fields = tuple((field, "ASCENDING") for field in base_fields)
    sorts = list(common_sorts)
    if include_category_sort and "category" not in base_fields:
        sorts.extend([("category", "ASCENDING"), ("category", "DESCENDING")])
    for sort in sorts:
        add(eq_fields + (sort,))


# Base indexes that aren't covered by helper
add([( "flagLow", "ASCENDING"), ("updatedAt", "DESCENDING")])
add([("flagExpiringSoon", "ASCENDING"), ("earliestExpiresAt", "ASCENDING")])
add([("flagStale", "ASCENDING"), ("updatedAt", "DESCENDING")])
add([("flagExcess", "ASCENDING"), ("updatedAt", "DESCENDING")])
add([("flagStale", "ASCENDING"), ("archived", "ASCENDING")])
add([("flagExpired", "ASCENDING"), ("archived", "ASCENDING")])

single_filters = ["category", "homeLocationId", "grantId", "useType"]

for field in single_filters:
    add_filter_indexes([field])

add_filter_indexes(["flagLow"], include_category_sort=True)
add_filter_indexes(["archived"], include_category_sort=True)
add_filter_indexes(["archived", "flagLow"], include_category_sort=True)

for field in single_filters:
    include_category = field != "category"
    add_filter_indexes([field, "flagLow"], include_category_sort=include_category)
    add_filter_indexes(["archived", field], include_category_sort=include_category)
    add_filter_indexes(["archived", field, "flagLow"], include_category_sort=include_category)

# Additional index for flagExpiringSoon when viewing archived items
add([("flagExpiringSoon", "ASCENDING"), ("archived", "ASCENDING"), ("earliestExpiresAt", "ASCENDING")])

# Lots collection
add([("archived", "ASCENDING"), ("expiresAt", "ASCENDING")], collection_group="lots")

# Usage logs collection
add([("itemId", "ASCENDING"), ("usedAt", "DESCENDING")], collection_group="usage_logs")

# Cart sessions collection
add([("status", "ASCENDING"), ("updatedAt", "DESCENDING")], collection_group="cart_sessions")
add([("status", "ASCENDING"), ("closedAt", "DESCENDING")], collection_group="cart_sessions")
add([("interventionId", "ASCENDING"), ("status", "ASCENDING"), ("closedAt", "DESCENDING")], collection_group="cart_sessions")

# Sort indexes for consistent output
indexes.sort(
    key=lambda idx: (
        idx["collectionGroup"],
        [(field["fieldPath"], field["order"]) for field in idx["fields"]],
    )
)

data = {"indexes": indexes, "fieldOverrides": []}

with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
