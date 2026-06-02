# QuickJS C bridge

Vendored from [abner/quickjs-c-bridge](https://github.com/abner/quickjs-c-bridge)
commit `7204d9b` with QuickJS `2021-03-27`.

The Linux build compiles the bridge for the current architecture instead of
using the x64-only binary shipped by `flutter_js`. Internal symbols are hidden
and linked with `-Bsymbolic-functions` because `libmpv` loads `libmujs`, which
also exports symbols such as `js_malloc` with an incompatible ABI.
