import csv
import sys
from collections import defaultdict

totals = defaultdict(float)
with open(sys.argv[1] if len(sys.argv) > 1 else "sales.csv") as f:
    for row in csv.DictReader(f):
        totals[row["region"]] += float(row["amount"])

for region in sorted(totals):
    print(f"{region}: {totals[region]:.2f}")
