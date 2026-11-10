// bytesdiff - the first-difference window of two byte texts.
namespace bytesdiff;

import std;

const MAX_SHOW: i64 = 48;

// first_diff gives the offset of the first byte that differs, or -1
// when the two are equal. A shorter side counts as a difference at
// its end.
fn first_diff(a: const u8[:], b: const u8[:]) -> i64 {
    var n = a.len;
    if b.len < n { n = b.len; }
    var i: i64 = 0;
    while i < n {
        if a[i] != b[i] { return i; }
        i = i + 1;
    }
    if a.len != b.len { return n; }
    return -1;
}

// show gives a printable window of `text` around `at`, at most
// MAX_SHOW bytes, with control bytes as \xNN. It appends to `out`.
fn show(out: u8[>..]&, text: const u8[:], at: i64) {
    var from = at - 8;
    if from < 0 { from = 0; }
    var to = at + MAX_SHOW;
    if to > text.len { to = text.len; }
    for i in from..to {
        let b = text[i];
        if b >= 32 && b < 127 { out.push(b); }
        else {
            out.push(92); out.push(120);
            let hi = b / 16;
            let lo = b % 16;
            if hi < 10 { out.push(48 + hi); } else { out.push(87 + hi); }
            if lo < 10 { out.push(48 + lo); } else { out.push(87 + lo); }
        }
    }
}
