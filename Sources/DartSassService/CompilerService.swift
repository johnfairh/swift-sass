public import DartSass
public import ServiceLifecycle

public actor CompilerService: Service {

    public let compiler: Compiler

    public init(compiler: Compiler) {
        self.compiler = compiler
    }

    public func run() async throws {
        // don't think we care if cancelled or asked to shutdown, same deal?
        try? await gracefulShutdown()
        await compiler.shutdownGracefully()
    }
}
