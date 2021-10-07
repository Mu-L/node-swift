import CNodeAPI
import Foundation

public protocol NodeModule {
    static var name: String { get }
    init() throws
    var exports: NodeValueConvertible { get }
}

private class ModulePriv {
    let name: UnsafeMutablePointer<CChar>
    let kind: NodeModule.Type
    init(name: UnsafeMutablePointer<CChar>, kind: NodeModule.Type) {
        self.name = name
        self.kind = kind
    }
    deinit { name.deallocate() }
}

// see comments in CNodeAPI/node_init.c, NodeSwiftHost/ctor.c
@_cdecl("node_swift_addon_register_func") @_spi(NodeAPI) public func _registerNodeSwiftModule(
    rawEnv: napi_env!,
    exports _: napi_value!,
    module: UnsafePointer<napi_module>!
) -> napi_value? {
    let moduleType = Unmanaged<ModulePriv>
        .fromOpaque(module.pointee.nm_priv)
        .takeUnretainedValue()
        .kind
    // the passed in `exports` is merely a convenience, ignore it
    return NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx in
        try moduleType.init().exports.rawValue()
    }
}

extension NodeModule {
    public static var name: String {
        var fullName = "\(self)"
        let suffix = "Module"
        if fullName.hasSuffix(suffix) {
            fullName.removeLast(suffix.count)
        }
        return fullName
    }

    public static func main() {
        guard let mod = node_swift_get_thread_module() else {
            nodeFatalError("NodeSwift module \(self) did not register itself correctly")
        }

        // strongly retains modname
        let priv = ModulePriv(name: name.copiedCString(), kind: Self.self)
        let modname = UnsafePointer(priv.name)

        mod.pointee.nm_version = NAPI_MODULE_VERSION
        mod.pointee.nm_filename = modname
        mod.pointee.nm_modname = modname
        mod.pointee.nm_priv = Unmanaged.passRetained(priv).toOpaque()

        napi_module_register(mod)
    }
}
