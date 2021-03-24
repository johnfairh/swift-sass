//
//  CompilerFunction.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// A Sass compiler function.
///
/// A compiler function is an opaque function defined by the Sass compiler that can be passed
/// as an argument to or returned by a `SassFunction`.
///
/// Right now there is no way to explicitly request they be executed; all you can do with this
/// type is validate that it appears when you expect it to and pass it back to the compiler when needed.
public final class SassCompilerFunction: SassValue {
    // MARK: Properties

    /// The function ID.  Opaque to users, meaningful to Sass implementations.
    public let id: Int

    /// Create a new compiler function.  Unless you're implementing or mocking an interface
    /// from a Sass compiler you don't need this. :nodoc:
    public init(id: Int) {
        self.id = id
    }

    // MARK: Misc

    /// Compiler functions are equal if they have the same ID and apply to the same compilation.
    /// We only test the first part of that so watch out.
    public static func == (lhs: SassCompilerFunction, rhs: SassCompilerFunction) -> Bool {
        lhs.id == rhs.id
    }

    /// Hash the compiler function
    public override func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(compilerFunction: self)
    }

    public override var description: String {
        "CompilerFunction(\(id))"
    }
}

extension SassValue {
    /// Reinterpret the value as a compiler function.
    /// - throws: `SassFunctionError.wrongType(...)` if it isn't a compiler function.
    public func asCompilerFunction() throws -> SassCompilerFunction {
        guard let selfCompilerFunction = self as? SassCompilerFunction else {
            throw SassFunctionError.wrongType(expected: "SassCompilerFunction", actual: self)
        }
        return selfCompilerFunction
    }
}
