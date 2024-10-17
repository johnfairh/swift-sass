//
//  Deprecation.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

internal import Semver

/// A `Deprecation` refers to a specific feature of the Sass compiler that is deprecated or planned to
/// become deprecated.
///
/// By default, using a deprecated feature  causes a warning -- that is, a `CompilerMessage` with
/// type `CompilerMessage.Kind.deprecation`.  In some future release of the compiler,
/// use of the deprecated feature will cause an error instead.
///
/// You can customize a Sass `Compiler`'s treatment of deprecated behaviours using a `DeprecationControl`
/// to create the compiler instance.  Each individual deprecation can be ignored or promoted to an error.  You can also
/// opt in  to *future* deprecations -- features that do not currently cause a deprecation warning but are planned to do
/// so in an upcoming release of Dart Sass.
public enum Deprecation: Hashable, Sendable, CustomStringConvertible {
    // MARK: Kinds

    /// A specific Sass deprecation.  See [the Sass docs](https://sass-lang.com/documentation/js-api/interfaces/deprecations/)
    /// for a description of what each of these means.
    case id(ID)

    /// A specific Sass deprecation whose ID has not been included in the `ID` enumeration for some reason.
    /// This is a workaround for development mistakes / release schedules  - ideally you won't need to use it!
    case custom(String)

    /// A version number for the Sass compiler meaning "every deprecation known to this level of the compiler".
    /// This may not be supported for all facets of `DeprecationControl` -- the Dart Sass compiler supports
    /// it only for `fatal` deprecations.
    case version(String)

    // MARK: Deprecation IDs

    /// The set of known deprecation IDs.  See [the Sass docs](https://sass-lang.com/documentation/js-api/interfaces/deprecations/).
    public enum ID: String, Sendable {
        /// [abs-percent](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#abs_percent)
        case absPercent = "abs-percent"
        /// [bogus-combinators](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#bogus_combinators)
        case bogusCombinators = "bogus-combinators"
        /// [call-string](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#call_string)
        case callString = "call-string"
        /// [color-4-api](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#color_4_api)
        case color4Api = "color-4-api"
        /// [color-functions](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#color_functions)
        case colorFunctions = "color-functions"
        /// [color-module-compat](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#color_module_compat)
        case colorModuleCompat = "color-module-compat"
        /// [css-function-mixin](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#css_function_mixin)
        case cssFunctionMixin = "css-function-mixin"
        /// [duplicate-var-flags](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#duplicate_var_flags)
        case duplicateVarFlags = "duplicate-var-flags"
        /// [elseif](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#elseif)
        case elseif = "elseif"
        /// [feature-exists](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#feature_exists)
        case featureExists = "feature-exists"
        /// [fs-importer-cwd](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#fs_importer_cwd)
        case fsImporterCwd = "fs-importer-cwd"
        /// [function-units](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#function_units)
        case functionUnits = "function-units"
        /// [global-builtin](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#global_builtin)
        case globalBuiltin = "global-builtin"
        /// [import](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#import)
        case `import` = "import"
        /// [legacy-js-api](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#legacy_js_api)
        case legacyJSApi = "legacy-js-api"
        /// [mixed-decls](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#mixed_decls)
        case mixedDecls = "mixed-decls"
        /// [moz-document](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#moz_document)
        case mozDocument = "moz-document"
        /// [new-global](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#new_global)
        case newGlobal = "new-global"
        /// [null-alpha](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#null_alpha)
        case nullAlpha = "null-alpha"
        /// [relative-canonical](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#relative_canonical)
        case relativeCanonical = "relative-canonical"
        /// [slash-div](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#slash_div)
        case slashDiv = "slash-div"
        /// [strict-unary](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#strict_unary)
        case strictUnary = "strict-unary"
        /// [user-authored](https://sass-lang.com/documentation/js-api/interfaces/deprecations/#user_authored)
        case userAuthored = "user-authored"
    }
    // currently known: 22 + userAuthored

    // MARK: Serialization

    /// Create a `Deprecation` from a string, guessing at the type from its format.
    public init(_ string: String) {
        if let id = ID(rawValue: string) {
            self = .id(id)
        } else if let semver = try? Semver(string: string) {
            self = .version(semver.toString())
        } else {
            self = .custom(string)
        }
    }

    /// A string representing the deprecation.
    ///
    /// Should round-trip with `init(_:)`.
    public var description: String {
        switch self {
        case .custom(let str), .version(let str): str
        case .id(let id): id.rawValue
        }
    }
}

/// A `Compiler`'s deprecation settings.
///
/// Indicates which `Deprecation`s should be fatal, silenced, or eagerly adopted.
public struct DeprecationControl: Sendable {
    /// The set of deprecations to be treated as compiler errors.
    public let fatal: Set<Deprecation>
    /// The set of deprecations to be ignored.
    public let silenced: Set<Deprecation>
    /// The set of future deprecations to be opted-in early.
    public let future: Set<Deprecation>

    /// Create a new `DeprecationControl`.
    ///
    /// Making mistakes with these -- for example passing an unknown deprecation string,
    /// or putting the same deprecation in multiple places in confusing ways -- is reported
    /// through warnings from the Sass compiler when you compile a stylesheet.
    public init(fatal: any Sequence<Deprecation> = [],
                silenced: any Sequence<Deprecation> = [],
                future: any Sequence<Deprecation> = []) {
        self.fatal = Set(fatal)
        self.silenced = Set(silenced)
        self.future = Set(future)
    }
}

extension Set where Element == Deprecation {
    var asStrings: [String] {
        Array(map(\.description))
    }
}
