// Scoped tests, a fixture and a case table. The tests need no begin
// and end calls: run does both.
import std;
import testkit from "..";

struct Db { rows: i64 }

// with_db is a fixture. It sets up, runs the block, then tears down.
fn with_db<F>(t: testkit::T&) {
    var db = Db { rows: 3 };
    F(t, db);
    print("db closed");
}

fn square(n: i64) -> i64 { return n * n; }

fn main() {
    var t = testkit::new_t();

    testkit::run(t, "test_rows") { tt =>
        with_db(tt) { t2, db => testkit::eq_i64(t2, db.rows, 3) };
    };

    testkit::run(t, "test_square") { tt =>
        testkit::cases(tt, "n", 4) { t2, i => testkit::eq_i64(t2, square(i), i * i) };
    };

    testkit::finish(t);
}
