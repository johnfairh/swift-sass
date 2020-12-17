Write a custom importer by implementing one of the `Importer` protocols and
passing an instance wrapped in an `ImportResolver` to the compiler.  A
custom importer can be scoped either to an individual compilation or
to all a compiler's compilations.
