import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
public final class LaunchAtLoginStore: ObservableObject {
    @Published public private(set) var status: SMAppService.Status
    @Published public private(set) var errorMessage: String?

    private let service: any LoginItemService

    public convenience init() {
        self.init(service: SystemLoginItemService())
    }

    init(service: any LoginItemService) {
        self.service = service
        self.status = service.status
    }

    // A pending request remains checked so the user can cancel it before granting approval.
    public var isRequested: Bool {
        status == .enabled || status == .requiresApproval
    }

    public func refresh() {
        status = service.status
    }

    public func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        refresh()
        guard enabled != isRequested else {
            return
        }

        defer { refresh() }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
