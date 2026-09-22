// Example VillageSQL extension (v3 SDK) shipped as a separate snap.
//   SELECT hello('snap');  -- 'Hello, snap!'
//   SELECT shout('snap');  -- 'SNAP!'
#include <villagesql/vsql.h>

#include <algorithm>
#include <cctype>
#include <string>

using namespace vsql;

// Copy s into the result buffer, or raise an error if it does not fit
// (StringResult::set would silently truncate).
static void write_string(StringResult &out, const std::string &s, const char *what) {
  if (s.size() > out.buffer().size()) {
    out.error(what);
    return;
  }
  out.set(s);
}

void hello_impl(StringArg name, StringResult out) {
  if (name.is_null()) {
    out.set_null();
    return;
  }
  write_string(out, "Hello, " + std::string(name.value()) + "!", "hello: name too long");
}

void shout_impl(StringArg input, StringResult out) {
  if (input.is_null()) {
    out.set_null();
    return;
  }
  std::string s(input.value());
  std::transform(s.begin(), s.end(), s.begin(),
                 [](unsigned char c) { return std::toupper(c); });
  write_string(out, s + "!", "shout: input too long");
}

VEF_GENERATE_ENTRY_POINTS(
    make_extension()
        .func(make_func<&hello_impl>("hello").returns(STRING).param(STRING).deterministic().build())
        .func(make_func<&shout_impl>("shout").returns(STRING).param(STRING).deterministic().build()))
