// The patterns that the README shows: a fixture that a test overrides,
// one test function for each subtest of a group, and a text dump of a
// value that eq_text compares. Each pattern runs here, so the README
// claims what this program shows.
import std;
import testkit from "..";

struct Db { rows: i64 }

// The fixture takes the rows of the database as a value. A caller that
// wants another database passes another value: that is the override.
fn with_rows<F>(t: testkit::T&, rows: i64) {
    var db = Db { rows: rows };
    F(t, db);
    print("closed ", rows);
}

// dump writes a stable text of a Db. A check compares that text, so a
// failure shows both sides.
fn dump(out: u8[>..]&, db: Db) {
    format(out, "Db{rows=", db.rows, "}");
}

fn test_grid_small(t: testkit::T&) { testkit::eq_i64(t, 1 + 1, 2); }
fn test_grid_large(t: testkit::T&) { testkit::eq_i64(t, 2 * 2, 4); }
fn test_other(t: testkit::T&) { testkit::eq_i64(t, 0, 0); }

fn main() {
    var t = testkit::new_t();

    testkit::run(t, "default fixture") { tt =>
        with_rows(tt, 3) { t2, db => testkit::eq_i64(t2, db.rows, 3) };
    };
    testkit::run(t, "overridden fixture") { tt =>
        with_rows(tt, 7) { t2, db => testkit::eq_i64(t2, db.rows, 7) };
    };

    testkit::run(t, "dump") { tt =>
        with_rows(tt, 5) { t2, db =>
            var text: u8[>..] = [];
            dump(text, db);
            testkit::eq_text(t2, text[..], "Db{rows=5}");
        };
    };

    // A group of test functions shares a prefix. The pattern of the
    // run flag picks the group, as it picks a group of subtests.
    assert(testkit::matches("test_grid", "test_grid_small"));
    assert(testkit::matches("test_grid", "test_grid_large"));
    assert(!testkit::matches("test_grid", "test_other"));
    assert(testkit::matches("^test_grid_(small|large)$", "test_grid_large"));
    assert(!testkit::matches("^test_grid_(small)$", "test_grid_large"));

    test_grid_small(t);
    test_grid_large(t);
    test_other(t);
    assert(t.fail_tests == 0);
    print("patterns pass");
}
