const std = @import("std");

/// Fuzzy match: checks if all characters in query appear in target in order
pub fn fuzzyMatch(query: []const u8, target: []const u8) bool {
    if (query.len == 0) return true;
    if (target.len == 0) return false;

    var query_idx: usize = 0;
    var target_idx: usize = 0;

    while (query_idx < query.len and target_idx < target.len) {
        const q_char = std.ascii.toLower(query[query_idx]);
        const t_char = std.ascii.toLower(target[target_idx]);

        if (q_char == t_char) {
            query_idx += 1;
        }
        target_idx += 1;
    }

    return query_idx == query.len;
}

/// Score a match (higher is better)
/// Rewards: consecutive matches, word start matches, exact matches
pub fn fuzzyScore(query: []const u8, target: []const u8) i32 {
    if (query.len == 0) return 0;
    if (target.len == 0) return -1000;

    var score: i32 = 0;
    var query_idx: usize = 0;
    var target_idx: usize = 0;
    var consecutive: i32 = 0;
    var prev_match_idx: ?usize = null;

    while (query_idx < query.len and target_idx < target.len) {
        const q_char = std.ascii.toLower(query[query_idx]);
        const t_char = std.ascii.toLower(target[target_idx]);

        if (q_char == t_char) {
            // Consecutive match bonus
            if (prev_match_idx) |prev| {
                if (target_idx == prev + 1) {
                    consecutive += 1;
                    score += consecutive * 3;
                } else {
                    consecutive = 0;
                    score += 1;
                }
            } else {
                score += 1;
            }

            // Word start bonus
            if (target_idx == 0 or isWordBoundary(target[target_idx - 1])) {
                score += 5;
            }

            // Case match bonus
            if (query[query_idx] == target[target_idx]) {
                score += 1;
            }

            prev_match_idx = target_idx;
            query_idx += 1;
        }
        target_idx += 1;
    }

    // Didn't match all query characters
    if (query_idx < query.len) {
        return -1000;
    }

    // Exact match bonus
    if (std.ascii.eqlIgnoreCase(query, target)) {
        score += 100;
    }

    // Shorter targets are better (more precise match)
    score -= @divTrunc(@as(i32, @intCast(target.len)), 4);

    return score;
}

fn isWordBoundary(char: u8) bool {
    return char == ' ' or char == '_' or char == '-' or char == '.' or char == '/';
}

/// Sort elements by match score (descending)
pub fn sortByScore(comptime T: type, items: []T, query: []const u8, getDisplayName: fn (*const T) []const u8) void {
    std.sort.insertion(T, items, .{ .query = query, .getDisplayName = getDisplayName }, struct {
        query: []const u8,
        getDisplayName: fn (*const T) []const u8,

        pub fn lessThan(ctx: @This(), a: T, b: T) bool {
            const score_a = fuzzyScore(ctx.query, ctx.getDisplayName(&a));
            const score_b = fuzzyScore(ctx.query, ctx.getDisplayName(&b));
            return score_a > score_b; // Higher score first
        }
    }.lessThan);
}

// Tests
test "fuzzyMatch basic" {
    try std.testing.expect(fuzzyMatch("abc", "abc"));
    try std.testing.expect(fuzzyMatch("abc", "aXbXc"));
    try std.testing.expect(fuzzyMatch("ac", "abc"));
    try std.testing.expect(!fuzzyMatch("abc", "ab"));
    try std.testing.expect(!fuzzyMatch("abc", ""));
    try std.testing.expect(fuzzyMatch("", "anything"));
}

test "fuzzyMatch case insensitive" {
    try std.testing.expect(fuzzyMatch("ABC", "abc"));
    try std.testing.expect(fuzzyMatch("abc", "ABC"));
    try std.testing.expect(fuzzyMatch("aBc", "AbC"));
}

test "fuzzyScore ordering" {
    // Exact match should score highest
    const exact = fuzzyScore("save", "save");
    const prefix = fuzzyScore("save", "save as");
    const scattered = fuzzyScore("save", "sXXaXXvXXe");

    try std.testing.expect(exact > prefix);
    try std.testing.expect(prefix > scattered);
}

test "fuzzyMatch edge cases" {
    // Single character
    try std.testing.expect(fuzzyMatch("a", "a"));
    try std.testing.expect(fuzzyMatch("a", "abc"));
    try std.testing.expect(!fuzzyMatch("z", "abc"));

    // Repeated characters
    try std.testing.expect(fuzzyMatch("aa", "aaa"));
    try std.testing.expect(!fuzzyMatch("aaa", "aa"));

    // Special characters
    try std.testing.expect(fuzzyMatch("_", "hello_world"));
    try std.testing.expect(fuzzyMatch(".", "file.txt"));
}

test "fuzzyScore word boundaries" {
    // Word start should score higher when it's the first match
    const word_start = fuzzyScore("ab", "a_b");
    const mid_word = fuzzyScore("ab", "aXb");

    try std.testing.expect(word_start > mid_word);
}

test "fuzzyScore consecutive matches" {
    // Consecutive matches should score higher
    const consecutive = fuzzyScore("abc", "abcdef");
    const scattered = fuzzyScore("abc", "aXXbXXc");

    try std.testing.expect(consecutive > scattered);
}

test "fuzzyScore no match" {
    try std.testing.expect(fuzzyScore("xyz", "abc") == -1000);
    try std.testing.expect(fuzzyScore("abc", "") == -1000);
}

test "isWordBoundary" {
    try std.testing.expect(isWordBoundary(' '));
    try std.testing.expect(isWordBoundary('_'));
    try std.testing.expect(isWordBoundary('-'));
    try std.testing.expect(isWordBoundary('.'));
    try std.testing.expect(isWordBoundary('/'));
    try std.testing.expect(!isWordBoundary('a'));
    try std.testing.expect(!isWordBoundary('0'));
}
