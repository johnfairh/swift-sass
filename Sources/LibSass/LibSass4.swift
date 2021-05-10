//
//  LibSass4.swift
//  LibSass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import CLibSass4
import struct Foundation.URL

// Wrappers around the C API to work around the Swift importer's disdain for
// opaque types and to hide some of the bizarre bits of the libsass API.

// Namespace
enum LibSass4 {
    static var version: String {
        String(safeCString: libsass_version())
    }

    // Current directory is very aggressively cached.  We avoid using it
    // everywhere except when users refuse to give paths to inline stylesheets
    // that have @import-type rules.
    static func chdir(to path: String) {
        sass_chdir(path)
    }

    /// struct SassCompiler
    final class Compiler {
        private let ptr: OpaquePointer
        private let owned: Bool
        private var associatedObjects: [AnyObject] = []

        init() {
            ptr = sass_make_compiler()
            owned = true
        }

        init(ptr: OpaquePointer!) {
            self.ptr = ptr
            self.owned = false
        }

        deinit {
            if owned {
                sass_delete_compiler(ptr)
            }
        }

        // Setter methods rather than properties because some of them are
        // set-only and we don't need the getters for those that do have them.

        func set(entryPoint mainImport: Import) {
            sass_compiler_set_entry_point(ptr, mainImport.ptr) // does not take ownership
        }

        func set(style: SassOutputStyle) {
            sass_compiler_set_output_style(ptr, style)
        }

        func enableSourceMap() {
            sass_compiler_set_srcmap_mode(ptr, SASS_SRCMAP_CREATE)
        }

        func set(sourceMapEmbedContents value: Bool) {
            sass_compiler_set_srcmap_embed_contents(ptr, value)
        }

        func set(precision: Int32) {
            sass_compiler_set_precision(ptr, precision)
        }

        func set(loggerColors enable: Bool) {
            sass_compiler_set_logger_colors(ptr, enable)
        }

        func set(loggerUnicode enable: Bool) {
            sass_compiler_set_logger_unicode(ptr, enable)
        }

        func set(outputPath: URL) {
            sass_compiler_set_output_path(ptr, outputPath.path)
        }

        func parseCompileRender() {
            sass_compiler_parse(ptr)
            sass_compiler_compile(ptr)
            sass_compiler_render(ptr)
        }

        var sourceMapString: String? {
            let cString = sass_compiler_get_srcmap_string(ptr)
            return cString.flatMap { String(cString: $0) }
        }

        var error: Error? {
            sass_compiler_get_error(ptr).flatMap {
                Error(ptr: $0)
            }
        }

        var outputString: String {
            String(safeCString: sass_compiler_get_output_string(ptr))
        }

        var warningString: String {
            String(safeCString: sass_compiler_get_warn_string(ptr))
        }

        var lastImport: Import {
            Import(ptr: sass_compiler_get_last_import(ptr))
        }

        func add(includePath: String) {
            sass_compiler_add_include_paths(ptr, includePath)
        }

        func add(customImporter: Importer) {
            let refs = customImporter.makeUnowned()
            associatedObjects.append(refs.swift)
            sass_compiler_add_custom_importer(ptr, refs.c)
        }

        func add(customFunction: Function) {
            let refs = customFunction.makeUnowned()
            associatedObjects.append(refs.swift)
            sass_compiler_add_custom_function(ptr, refs.c)
        }
    }

    /// struct SassImport
    final class Import {
        fileprivate let ptr: OpaquePointer
        private var owned: Bool

        init(string: String, fileURL: URL?, syntax: SassImportSyntax) {
            self.ptr = sass_make_content_import(string.sassDup, fileURL?.path)
            self.owned = true
            set(syntax: syntax)
        }

        init(fileURL: URL) {
            self.ptr = sass_make_file_import(fileURL.path)
            self.owned = true
        }

        init(errorMessage: String) {
            self.ptr = sass_make_content_import(nil, nil) // sure..
            self.owned = true
            sass_import_set_error_message(ptr, errorMessage)
        }

        fileprivate init(ptr: OpaquePointer!) {
            self.ptr = ptr
            self.owned = false
        }

        func set(syntax: SassImportSyntax) {
            sass_import_set_syntax(ptr, syntax)
        }

        var absPath: URL {
            URL(fileURLWithPath: String(safeCString: sass_import_get_abs_path(ptr)))
        }

        fileprivate func makeUnowned() -> OpaquePointer {
            precondition(owned)
            owned = false
            return ptr
        }

        deinit {
            if owned {
                sass_delete_import(ptr)
            }
        }
    }

    /// struct SassError
    final class Error {
        private let ptr: OpaquePointer

        fileprivate init?(ptr: OpaquePointer) {
            self.ptr = ptr
            if sass_error_get_status(ptr) == 0 {
                // Not actually an error, and don't think about what 'status' means....
                return nil
            }
        }

        var message: String {
            String(safeCString: sass_error_get_string(ptr))
        }

        var formatted: String {
            String(safeCString: sass_error_get_formatted(ptr))
        }

        var lineNumber: Int {
            sass_error_get_line(ptr)
        }

        var columnNumber: Int {
            sass_error_get_column(ptr)
        }

        var fileURL: URL? {
            sass_error_get_path(ptr).flatMap { URL(fileURLWithPath: String(cString: $0)) }
        }

        var stackTrace: [Trace] {
            let nTraces = sass_error_count_traces(ptr)
            return (0..<nTraces)
                .map { .init(ptr: sass_error_get_trace(ptr, $0)) }
        }
    }

    /// struct SassTrace
    final class Trace {
        fileprivate let ptr: OpaquePointer
        private let spanPtr: OpaquePointer

        fileprivate init(ptr: OpaquePointer) {
            self.ptr = ptr
            self.spanPtr = sass_trace_get_srcspan(ptr)
        }

        var name: String {
            String(safeCString: sass_trace_get_name(ptr))
        }

        var lineNumber: Int {
            sass_srcspan_get_src_line(spanPtr) // 1-based
        }

        var columnNumber: Int {
            sass_srcspan_get_src_column(spanPtr) // 1-based
        }

        var fileURL: URL {
            let sourcePtr = sass_srcspan_get_source(spanPtr)
            return URL(fileURLWithPath: String(cString: sass_source_get_abs_path(sourcePtr)))
        }
    }

    /// struct SassImporter
    final class Importer {
        private let ptr: OpaquePointer
        private var _swiftContext: CallbackGlue?
        private var owned: Bool { _swiftContext != nil }
        private var swiftContext: CallbackGlue {
            get { _swiftContext! }
            set { _swiftContext = newValue }
        }

        typealias Callback = (String, Compiler) -> ImportList?

        /// Shim client's callback through C.  We hold 1 refcount on this (in Swift) until added to a
        /// Compiler, at which point we move it over there for the compiler lifetime.  The C version
        /// does not have an associated ref.
        private final class CallbackGlue {
            let callback: Callback
            init(_ callback: @escaping Callback) { self.callback = callback }
        }

        init(priority: Double, callback: @escaping Callback) {
            let glue = CallbackGlue(callback)
            let rawGlue = Unmanaged<CallbackGlue>.passUnretained(glue).toOpaque()

            func importerLambda(url: UnsafePointer<Int8>?, importerPtr: OpaquePointer?, compilerPtr: OpaquePointer?) -> OpaquePointer? {
                let rawGlue = sass_importer_get_cookie(importerPtr)!
                let compiler = Compiler(ptr: compilerPtr)
                let lambda = Unmanaged<CallbackGlue>.fromOpaque(rawGlue).takeUnretainedValue()
                guard let list = lambda.callback(String(safeCString: url), compiler) else {
                    return nil
                }
                return list.makeUnowned()
            }

            self.ptr = sass_make_importer(importerLambda, priority, rawGlue)
            self.swiftContext = glue
        }

        fileprivate func makeUnowned() -> (swift: AnyObject, c: OpaquePointer) {
            precondition(owned)
            defer { _swiftContext = nil }
            return (swiftContext, ptr)
        }

        deinit {
            if owned {
                sass_delete_importer(ptr)
            }
        }
    }

    /// struct SassImportList
    final class ImportList {
        private let ptr: OpaquePointer
        private var owned: Bool

        init() {
            ptr = sass_make_import_list()
            owned = true
        }

        convenience init(_ singleImport: Import) {
            self.init()
            push(import: singleImport)
        }

        deinit {
            if owned {
                sass_delete_import_list(ptr)
            }
        }

        fileprivate func makeUnowned() -> OpaquePointer {
            precondition(owned)
            owned = false
            return ptr
        }

        func push(import next: Import) {
            sass_import_list_push(ptr, next.makeUnowned())
        }
    }

    /// struct SassFunction
    final class Function {
        private let ptr: OpaquePointer
        private var _swiftContext: CallbackGlue?
        private var owned: Bool { _swiftContext != nil }
        private var swiftContext: CallbackGlue {
            get { _swiftContext! }
            set { _swiftContext = newValue }
        }

        typealias Callback = (Value, Compiler) -> Value

        /// Shim client's callback through C.  We hold 1 refcount on this (in Swift) until added to a
        /// Compiler, at which point we move it over there for the compiler lifetime.  The C version
        /// does not have an associated ref.
        private final class CallbackGlue {
            let callback: Callback
            init(_ callback: @escaping Callback) { self.callback = callback }
        }

        init(signature: String, callback: @escaping Callback) {
            let glue = CallbackGlue(callback)
            let rawGlue = Unmanaged<CallbackGlue>.passUnretained(glue).toOpaque()

            func functionLambda(argsValuePtr: OpaquePointer?,
                                compilerPtr: OpaquePointer?,
                                cookie: UnsafeMutableRawPointer!) -> OpaquePointer? {
                let argsValue = Value(argsValuePtr)
                let compiler = Compiler(ptr: compilerPtr)
                let lambda = Unmanaged<CallbackGlue>.fromOpaque(cookie).takeUnretainedValue()
                let returnValue = lambda.callback(argsValue, compiler)
                return returnValue.ensureUnowned()
            }

            self.ptr = sass_make_function(signature, functionLambda, rawGlue)
            self.swiftContext = glue
        }

        fileprivate func makeUnowned() -> (swift: AnyObject, c: OpaquePointer) {
            precondition(owned)
            defer { _swiftContext = nil }
            return (swiftContext, ptr)
        }

        deinit {
            if owned {
                sass_delete_function(ptr)
            }
        }
    }

    /// struct SassValue
    final class Value {
        fileprivate let ptr: OpaquePointer
        private var owned: Bool

        fileprivate init(_ ptr: OpaquePointer!) {
            self.ptr = ptr
            self.owned = false
        }

        deinit {
            if owned {
                sass_delete_value(ptr)
            }
        }

        fileprivate func ensureUnowned() -> OpaquePointer {
            // can't assert owned here: passing opaque value
            // back to compiler means it is never owned by us.
            owned = false
            return ptr
        }

        // kind
        var kind: SassValueType {
            sass_value_get_tag(ptr)
        }

        // null
        init() {
            self.ptr = sass_make_null()
            self.owned = true
        }

        // error
        init(error: String) {
            self.ptr = sass_make_error(error)
            self.owned = true
        }

        // boolean
        init(bool: Bool) {
            self.ptr = sass_make_boolean(bool)
            self.owned = true
        }
        var boolValue: Bool { sass_boolean_get_value(ptr) }

        // string
        init(string: String, isQuoted: Bool) {
            self.ptr = sass_make_string(string, isQuoted)
            self.owned = true
        }
        var stringValue: String { String(safeCString: sass_string_get_value(ptr)) }
        var stringIsQuoted: Bool { sass_string_is_quoted(ptr) }

        // number
        init(number: Double, units: String) {
            self.ptr = sass_make_number(number, units)
            self.owned = true
        }
        var numberValue: Double { sass_number_get_value(ptr) }
        var numberUnits: String { String(safeCString: sass_number_get_unit(ptr)) }

        // color
        init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.ptr = sass_make_color(red, green, blue, alpha)
            self.owned = true
        }
        var colorRed: Double { sass_color_get_r(ptr) }
        var colorGreen: Double { sass_color_get_g(ptr) }
        var colorBlue: Double { sass_color_get_b(ptr) }
        var colorAlpha: Double { sass_color_get_a(ptr) }

        // list
        init(values: [Value], hasBrackets: Bool, separator: SassSeparator) {
            self.ptr = sass_make_list(separator, hasBrackets)
            self.owned = true
            values.forEach { sass_list_push(self.ptr, $0.ptr) }
        }

        var listSize: Int { sass_list_get_size(ptr) }
        var listHasBrackets: Bool { sass_list_get_is_bracketed(ptr) }
        var listSeparator: SassSeparator { sass_list_get_separator(ptr) }
        subscript(index: Int) -> Value { Value(sass_list_at(ptr, index)) }

        // map
        init(pairs: [(Value, Value)]) {
            self.ptr = sass_make_map()
            self.owned = true
            pairs.forEach { sass_map_set(ptr, $0.0.ptr, $0.1.ptr) }
        }

        var mapIterator: MapIterator {
            MapIterator(mapValue: self)
        }

        // Int passthrough (for CompilerFunction)
        init(pointerValue: Int) {
            self.ptr = OpaquePointer(bitPattern: pointerValue)!
            self.owned = false
        }

        var pointerValue: Int {
            Int(bitPattern: ptr)
        }
    }

    // struct SassMapIterator
    final class MapIterator {
        private let ptr: OpaquePointer

        fileprivate init(mapValue: Value) {
            ptr = sass_map_make_iterator(mapValue.ptr)
        }

        deinit {
            sass_map_delete_iterator(ptr)
        }

        var isExhausted: Bool {
            sass_map_iterator_exhausted(ptr)
        }

        func next() {
            sass_map_iterator_next(ptr)
        }

        var key: Value {
            Value(sass_map_iterator_get_key(ptr))
        }

        var value: Value {
            Value(sass_map_iterator_get_value(ptr))
        }
    }

    static func dumpMemLeaks() {
        // sass_dump_mem_leaks()
    }
}

private extension String {
    init(safeCString: UnsafePointer<Int8>!) {
        if let safeCString = safeCString {
            self.init(cString: safeCString)
        } else {
            self.init()
        }
    }

    var sassDup: UnsafeMutablePointer<Int8> {
        sass_copy_c_string(self)
    }
}
