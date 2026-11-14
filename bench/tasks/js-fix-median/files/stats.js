function median(values) {
	const sorted = values.sort();
	const mid = Math.floor(sorted.length / 2);
	return sorted[mid];
}

module.exports = { median };
