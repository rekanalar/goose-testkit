// The test filter: the -run patterns of Go, the shard of a suite, and
// the retry count. The generated file of the testgen command calls
// filter once at the start of main.
namespace testkit;

// part_end gives the index of the next '/' at or after from, or the
// length of s when there is none.
fn part_end(s: const u8[:], from: i64) -> i64 {
    var i = from;
    while i < s.len && s[i] != 47 { i = i + 1; }
    return i;
}

// text_at reports whether pat sits in s at the index at.
fn text_at(s: const u8[:], pat: const u8[:], at: i64) -> bool {
    if at < 0 || at + pat.len > s.len { return false; }
    var k: i64 = 0;
    while k < pat.len {
        if s[at + k] != pat[k] { return false; }
        k = k + 1;
    }
    return true;
}

// part_ok reports whether one pattern part matches one name part. The
// part matches as text. A leading ^ anchors the start and a trailing $
// anchors the end. An empty part matches anything.
fn part_ok(pat: const u8[:], s: const u8[:]) -> bool {
    var core = pat;
    var head = false;
    var tail = false;
    if core.len > 0 && core[0] == 94 {
        head = true;
        core = core[1..core.len];
    }
    if core.len > 0 && core[core.len - 1] == 36 {
        tail = true;
        core = core[0..core.len - 1];
    }
    if head && tail { return s.len == core.len && text_at(s, core, 0); }
    if head { return text_at(s, core, 0); }
    if tail { return text_at(s, core, s.len - core.len); }
    var at: i64 = 0;
    while at + core.len <= s.len {
        if text_at(s, core, at) { return true; }
        at = at + 1;
    }
    return false;
}

// alt_ok matches one pattern against a test name, part by part. A
// name with fewer parts than the pattern runs when its parts match:
// the parent of a matching subtest runs. A pattern with fewer parts
// than the name selects the whole subtree.
fn alt_ok(pat: const u8[:], name: const u8[:]) -> bool {
    var pa: i64 = 0;
    var na: i64 = 0;
    while na <= name.len && pa <= pat.len {
        let ne = part_end(name, na);
        let pe = part_end(pat, pa);
        if !part_ok(pat[pa..pe], name[na..ne]) { return false; }
        na = ne + 1;
        pa = pe + 1;
    }
    return true;
}

// matches reports whether a name passes the -run pattern. A '|'
// separates alternative patterns. An empty pattern matches all.
fn matches(pat: const u8[:], name: const u8[:]) -> bool {
    if pat.len == 0 { return true; }
    var from: i64 = 0;
    while from <= pat.len {
        var to = from;
        while to < pat.len && pat[to] != 124 { to = to + 1; }
        if alt_ok(pat[from..to], name) { return true; }
        from = to + 1;
    }
    return false;
}

// shard_of gives the shard of a name, 0 to n - 1. It uses FNV-1a on
// 32 bits, so the same name lands in the same shard on every system.
fn shard_of(name: const u8[:], n: i64) -> i64 {
    var h: i64 = 2166136261;
    for b in name {
        h = ((h ^ b) * 16777619) & 4294967295;
    }
    return h % n;
}

// filter sets the options of this run. The run pattern follows Go: a
// part matches as text, ^ and $ anchor, | separates patterns, and a
// parent of a matching subtest runs. Shard i of n, counted from 1,
// runs the tests whose name hash mod n is i - 1. n of 0 turns the
// shard off. A count above 1 gives each test that many attempts.
fn filter(t: T&, run: const u8[:], shard_i: i64, shard_n: i64, count: i64) {
    t.pat = run;
    t.shard_i = shard_i;
    t.shard_n = shard_n;
    t.count = count;
}

// leave_out records a test that the filter or the shard left out. It
// counts as a skip, prints nothing, and does not run the block. The
// name stays out of the list of tests that ran.
fn leave_out(t: T&, name: const u8[:], by_shard: bool) {
    let names0 = t.names.len;
    let unlisted0 = t.unlisted;
    begin(t, name);
    t.skipped = true;
    if by_shard { t.sharded = t.sharded + 1; }
    else { t.filtered = t.filtered + 1; }
    end(t);
    t.names.resize(names0, 0);
    t.unlisted = unlisted0;
}
