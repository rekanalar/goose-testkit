// A sample suite for the testgen command.
//
// Regenerate the list and the options of a run with the command, from
// this directory:
//
//   goose build -o testgen ../../cmd/testgen.goose
//   ./testgen -run 'math' -shard 1/2 -count 2
//
// Then run the suite: goose run test/run.goose
import std;
import testkit from "../../..";
import _gen;

fn sum(a: i64, b: i64) -> i64 { return a + b; }
fn upper(c: u8) -> u8 { return c - 32; }

fn main() {
    var t = testkit::new_t();
    testkit::filter(t, _gen::run(), _gen::shard_i(), _gen::shard_n(), _gen::count());

    testkit::run(t, "math") { tt =>
        testkit::scope(tt, "sum") { t2 => testkit::eq_i64(t2, sum(2, 3), 5); };
        testkit::scope(tt, "negative") { t2 => testkit::eq_i64(t2, sum(-2, -3), -5); };
    };
    testkit::run(t, "text") { tt =>
        testkit::scope(tt, "upper") { t2 => testkit::eq_i64(t2, upper('a') as i64, 'A' as i64); };
        testkit::scope(tt, "equal") { t2 => testkit::eq_text(t2, "goose", "goose"); };
    };
    testkit::run(t, "flags") { tt => testkit::is_true(tt, true, "always"); };

    // The command writes the calls to the test functions of the suite.
    _gen::run_all(t);

    var names: u8[>..] = [];
    _gen::list(names);
    var found: i64 = 0;
    for b in names { if b == 10 { found = found + 1; } }
    print("testgen found ", found, " tests in the source");
    testkit::finish(t);
}
