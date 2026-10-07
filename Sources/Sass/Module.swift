//
//  Module.swift
//  Sass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// A Sass module.
///
/// Values representing modles can only be created by the compiler.  See [the Sass docs](https://sass-lang.com/documentation/values/modules/).
public final class SassModule: SassValue, @unchecked Sendable {
    // MARK: Properties

    /// The modle ID.  Opaque to users, meaningful to Sass implementations.
    public let id: Int

    /// Create a new modle.  Unless you're implementing or mocking an interface
    /// from a Sass compiler you don't need this.
    @_spi(SassCompilerProvider)
    public init(id: Int) {
        self.id = id
    }

    // MARK: Misc

    /// Modiles are equal if they have the same ID and apply to the same compilation.
    /// We only test the first part of that so watch out.
    public static func == (lhs: SassModule, rhs: SassModule) -> Bool {
        lhs.id == rhs.id
    }

    /// Hash the module
    public override func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(module: self)
    }

    public override var description: String {
        "Module(\(id))"
    }
}

extension SassValue {
    /// Reinterpret the value as a modle.
    /// - throws: `SassFunctionError.wrongType(...)` if it isn't a module.
    public func asModule() throws -> SassModule {
        guard let selfModule = self as? SassModule else {
            throw SassFunctionError.wrongType(expected: "SassModule", actual: self)
        }
        return selfModule
    }
}
