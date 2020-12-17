Define Swift implementations of
[Sass `@function`s](https://sass-lang.com/documentation/at-rules/function) by
declaring one of the `SassFunctionMap` types and passing it to the compiler.

Use the `SassValue` family of types within the function to exchange data with
the Sass compiler.

A set of functions can be scoped either to an individual compilation or to all
a compiler's compilations.
