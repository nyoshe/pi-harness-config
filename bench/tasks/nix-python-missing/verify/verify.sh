set -eu
expected=$(python3 summarize.py sales.csv)
test "$expected" = "$(cat result.txt)"
# The agent must not have edited the script or data to get there.
git diff --quiet "$BENCH_BASE_SHA" -- summarize.py sales.csv
