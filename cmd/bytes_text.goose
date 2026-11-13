// Byte and text helpers of testgen: numbers, suffixes, ordering and
// hashing of names and sources.
namespace bytes_text;

import std;

// parse_num reads a decimal number. It gives -1 for anything else.
fn parse_num(s: const u8[:]) -> i64 {
    if s.len == 0 || s.len > 9 { return -1; }
    var n: i64 = 0;
    for b in s {
        if b < 48 || b > 57 { return -1; }
        n = n * 10 + (b - 48);
    }
    return n;
}

// ends_with reports whether s ends with tail.
fn ends_with(s: const u8[:], tail: const u8[:]) -> bool {
    if s.len < tail.len { return false; }
    var k: i64 = 0;
    while k < tail.len {
        if s[s.len - tail.len + k] != tail[k] { return false; }
        k = k + 1;
    }
    return true;
}

// cmp orders two names bytewise.
fn cmp(a: const u8[:], b: const u8[:]) -> i64 {
    var k: i64 = 0;
    while k < a.len && k < b.len {
        if a[k] != b[k] { return (a[k] as i64) - b[k]; }
        k = k + 1;
    }
    return a.len - b.len;
}

// sort_lines sorts the lines of buf, each ended by a line feed, in the
// byte order of their bytes.
fn sort_lines(buf: u8[>..]&) {
    var starts: i64[>..] = [];
    var ends: i64[>..] = [];
    var at: i64 = 0;
    var p: i64 = 0;
    while p < buf.len {
        if buf[p] == 10 {
            starts.push(at);
            ends.push(p);
            at = p + 1;
        }
        p = p + 1;
    }
    var order: i64[>..] = [];
    for k in starts.len { order.push(k); }
    var x: i64 = 1;
    while x < order.len {
        let cur = order[x];
        var y = x;
        while y > 0 && cmp(buf[starts[order[y - 1]]..ends[order[y - 1]]], buf[starts[cur]..ends[cur]]) > 0 {
            order[y] = order[y - 1];
            y = y - 1;
        }
        order[y] = cur;
        x = x + 1;
    }
    var out: u8[>..] = [];
    for k in order.len {
        for b in buf[starts[order[k]]..ends[order[k]]] { out.push(b); }
        out.push(10);
    }
    buf.clear();
    for b in out { buf.push(b); }
}

// hash_bytes gives the hash of the bytes, as the shard hash does. A
// change of the bytes gives another hash.
fn hash_bytes(b: const u8[:]) -> i64 {
    var h: i64 = 2166136261;
    for x in b {
        h = ((h ^ x) * 16777619) & 4294967295;
    }
    return h;
}
