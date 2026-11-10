// The call-site lexer of the testgen command. It reads Goose source
// as bytes and finds each testkit::run and testkit::begin call that
// names its test with a string literal. It builds no syntax tree, so a
// name that the program builds at runtime stays invisible.
namespace testkit;

import std;

const LEX_MAX_NAME: i64 = 1024;

fn lex_is_ident(b: u8) -> bool {
    return (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95;
}

// at reports whether pat sits in src at the index i.
fn lex_at(src: const u8[:], i: i64, pat: const u8[:]) -> bool {
    if i + pat.len > src.len { return false; }
    var k: i64 = 0;
    while k < pat.len {
        if src[i + k] != pat[k] { return false; }
        k = k + 1;
    }
    return true;
}

// line_of gives the line, counted from 1, of the index i.
fn lex_line_of(src: const u8[:], i: i64) -> i64 {
    var line: i64 = 1;
    var k: i64 = 0;
    while k < i && k < src.len {
        if src[k] == 10 { line = line + 1; }
        k = k + 1;
    }
    return line;
}

// skip_quoted gives the index after the closing quote q of the
// literal that opens at i. It gives -1 when the line or the file ends
// first. A backslash skips the next byte.
fn lex_skip_quoted(src: const u8[:], i: i64, q: u8) -> i64 {
    var k = i + 1;
    while k < src.len {
        let b = src[k];
        if b == 92 {
            k = k + 2;
        } else if b == q {
            return k + 1;
        } else if b == 10 {
            return -1;
        } else {
            k = k + 1;
        }
    }
    return -1;
}

// call_len gives the length of the call opener at i, or 0 when none
// sits there. A call opener is testkit::run( or testkit::begin( that
// starts a word.
fn lex_call_len(src: const u8[:], i: i64) -> i64 {
    if i > 0 && lex_is_ident(src[i - 1]) { return 0; }
    if lex_at(src, i, "testkit::run(") { return 13; }
    if lex_at(src, i, "testkit::begin(") { return 15; }
    return 0;
}

// fault records a fault message and gives the line.
fn lex_fault(src: const u8[:], i: i64, msg: const u8[:], why: u8[>..]&) -> i64 {
    for b in msg { why.push(b); }
    return lex_line_of(src, i);
}

// call_name reads the name of the call whose arguments start at p. It
// appends the name and a line feed to out. It gives the index to go on
// from, or -1 on a fault, with the message in why. A call whose second
// argument is not a string literal gives no name.
fn lex_call_name(src: const u8[:], p: i64, out: u8[>..]&, why: u8[>..]&) -> i64 {
    var k = p;
    var depth: i64 = 0;
    while k < src.len {
        let b = src[k];
        if b == 34 || b == 39 {
            let e = lex_skip_quoted(src, k, b);
            if e < 0 { return -1 - lex_fault(src, k, "a string never ends", why); }
            k = e;
        } else if b == 40 {
            depth = depth + 1;
            k = k + 1;
        } else if b == 41 {
            if depth == 0 { return k; }
            depth = depth - 1;
            k = k + 1;
        } else if b == 44 && depth == 0 {
            break;
        } else {
            k = k + 1;
        }
    }
    if k >= src.len { return -1 - lex_fault(src, p, "a call never closes", why); }
    k = k + 1;
    while k < src.len && (src[k] == 32 || src[k] == 9 || src[k] == 10 || src[k] == 13) { k = k + 1; }
    if k >= src.len || src[k] != 34 { return k; }
    let e = lex_skip_quoted(src, k, 34);
    if e < 0 { return -1 - lex_fault(src, k, "a string never ends", why); }
    let name = src[k + 1..e - 1];
    if name.len == 0 { return -1 - lex_fault(src, k, "a test name is empty", why); }
    if name.len > LEX_MAX_NAME { return -1 - lex_fault(src, k, "a test name is longer than 1024 bytes", why); }
    for b in name {
        if b == 92 { return -1 - lex_fault(src, k, "a test name holds a backslash; write the name in plain text", why); }
        if b < 32 || b > 126 { return -1 - lex_fault(src, k, "a test name holds a byte outside printable ASCII", why); }
    }
    for b in name { out.push(b); }
    out.push(10);
    return e;
}

// scan appends the name of each test call site of src, each ended by
// a line feed. It gives 0 on success. On a fault it gives the line, and
// why holds the message.
fn lex_scan(src: const u8[:], out: u8[>..]&, why: u8[>..]&) -> i64 {
    var i: i64 = 0;
    while i < src.len {
        let b = src[i];
        if b == 47 && i + 1 < src.len && src[i + 1] == 47 {
            while i < src.len && src[i] != 10 { i = i + 1; }
        } else if b == 34 || b == 39 {
            let e = lex_skip_quoted(src, i, b);
            if e < 0 { return lex_fault(src, i, "a string never ends", why); }
            i = e;
        } else {
            let n = lex_call_len(src, i);
            if n == 0 {
                i = i + 1;
            } else {
                let r = lex_call_name(src, i + n, out, why);
                if r < 0 { return -1 - r; }
                i = r;
            }
        }
    }
    return 0;
}

// lex_put_safe appends s with each byte outside printable ASCII
// replaced by '?'. A message about a file name uses it, so a hostile
// name cannot write a control sequence to the terminal.
fn lex_put_safe(out: u8[>..]&, s: const u8[:]) {
    for b in s {
        if b < 32 || b > 126 { out.push('?'); }
        else { out.push(b); }
    }
}
