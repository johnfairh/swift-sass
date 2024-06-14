//
//  Mixin.swift
//  Sass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// A Sass mixin.
///
/// Values representing mixins can only be created by the compiler.  See [the Sass docs](https://sass-lang.com/documentation/values/mixins/).
public final class SassMixin: SassValue, @unchecked Sendable {
    // MARK: Properties

    /// The mixin ID.  Opaque to users, meaningful to Sass implementations.
    public let id: Int

    /// Create a new mixin.  Unless you're implementing or mocking an interface
    /// from a Sass compiler you don't need this.
    @_spi(SassCompilerProvider)
    public init(id: Int) {
        self.id = id
    }

    // MARK: Misc

    /// Mixins are equal if they have the same ID and apply to the same compilation.
    /// We only test the first part of that so watch out.
    public static func == (lhs: SassMixin, rhs: SassMixin) -> Bool {
        lhs.id == rhs.id
    }

    /// Hash the mixin
    public override func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(mixin: self)
    }

    public override var description: String {
        "Mixin(\(id))"
    }
}

extension SassValue {
    /// Reinterpret the value as a mixin.
    /// - throws: `SassFunctionError.wrongType(...)` if it isn't a mixin.
    public func asMixin() throws -> SassMixin {
        guard let selfMixin = self as? SassMixin else {
            throw SassFunctionError.wrongType(expected: "SassMixin", actual: self)
        }
        return selfMixin
    }
}
