//
//  LibSass.swift
//  SassLibSass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import LibSass4
import struct Foundation.URL

// Wrappers around the C API to work around the Swift importer's disdain for
// opaque types and to hide some of the bizarre bits of the libsass API.

// Namespace
enum LibSass {
    static var version: String {
        String(safeCString: libsass_version())
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
            mainImport.makeUnowned()
            sass_compiler_set_entry_point(ptr, mainImport.ptr)
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

        func set(loggerStyle: SassLoggerStyle) {
            sass_compiler_set_logger_style(ptr, loggerStyle)
        }

//        func set(sourceMapSourceRoot root: String) {
//            sass_compiler_set_srcmap_root(ptr, root)
//        }

        /// XXX this is wiping out warnings on each step?
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
            customImporter.makeUnowned().flatMap { associatedObjects.append($0) }
            sass_compiler_add_custom_importer(ptr, customImporter.ptr)
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

        var impPath: String {
            String(safeCString: sass_import_get_imp_path(ptr))
        }

        var absPath: String {
            String(safeCString: sass_import_get_abs_path(ptr))
        }

        fileprivate func makeUnowned() {
            precondition(owned)
            owned = false
        }

        deinit {
            if owned {
                sass_delete_import(ptr)
            }
        }
    }

    /// struct SassError
    final class Error {
        fileprivate let ptr: OpaquePointer

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
        fileprivate let ptr: OpaquePointer
        private var owned: Bool
        private var swiftContext: AnyObject?

        typealias Callback = (String, Importer, Compiler) -> ImportList?

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
                let importer = Importer(ptr: importerPtr)
                let compiler = Compiler(ptr: compilerPtr)
                let lambda = Unmanaged<CallbackGlue>.fromOpaque(importer.context!).takeUnretainedValue()
                guard let list = lambda.callback(String(safeCString: url), importer, compiler) else {
                    return nil
                }
                list.makeUnowned()
                return list.ptr
            }

            self.ptr = sass_make_importer(importerLambda, priority, rawGlue)
            self.swiftContext = glue
            self.owned = true
        }

        fileprivate init(ptr: OpaquePointer!) {
            self.ptr = ptr
            self.owned = false
            self.swiftContext = nil
        }

        fileprivate func makeUnowned() -> AnyObject? {
            precondition(owned)
            owned = false
            defer { swiftContext = nil }
            return swiftContext
        }

        deinit {
            if owned {
                sass_delete_importer(ptr)
            }
        }

        var context: UnsafeMutableRawPointer? {
            sass_importer_get_cookie(ptr)
        }
    }

    /// struct SassImportList
    final class ImportList {
        fileprivate let ptr: OpaquePointer
        private var owned: Bool

        init() {
            ptr = sass_make_import_list()
            owned = true
        }

        deinit {
            if owned {
                sass_delete_import_list(ptr)
            }
        }

        fileprivate func makeUnowned() {
            precondition(owned)
            owned = false
        }

        func push(import next: Import) {
            next.makeUnowned()
            sass_import_list_push(ptr, next.ptr)
        }
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
