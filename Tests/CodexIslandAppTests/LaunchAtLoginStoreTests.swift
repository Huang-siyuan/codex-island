import Foundation
import ServiceManagement
import Testing
@testable import CodexIslandCore

@MainActor
private final class TestLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var operationError: Error?
    var registerCount = 0
    var unregisterCount = 0

    func register() throws {
        registerCount += 1
        if let operationError {
            throw operationError
        }
        status = registrationStatus
    }

    func unregister() throws {
        unregisterCount += 1
        if let operationError {
            throw operationError
        }
        status = .notRegistered
    }
}

@MainActor
@Test
func launchAtLoginReadsSystemStateWithoutRegisteringOnLaunch() {
    let service = TestLoginItemService()
    service.status = .enabled
    let store = LaunchAtLoginStore(service: service)

    #expect(store.isRequested)
    #expect(service.registerCount == 0)
    #expect(service.unregisterCount == 0)
}

@MainActor
@Test(arguments: [SMAppService.Status.notRegistered, .notFound])
func launchAtLoginRegistersAndUnregistersOnlyWhenSelectionChanges(initialStatus: SMAppService.Status) {
    let service = TestLoginItemService()
    service.status = initialStatus
    let store = LaunchAtLoginStore(service: service)
    #expect(!store.isRequested)

    store.setEnabled(true)
    store.setEnabled(true)
    #expect(store.status == .enabled)
    #expect(store.isRequested)
    #expect(service.registerCount == 1)

    store.setEnabled(false)
    store.setEnabled(false)
    #expect(store.status == .notRegistered)
    #expect(!store.isRequested)
    #expect(service.unregisterCount == 1)
}

@MainActor
@Test
func launchAtLoginKeepsApprovalPendingDistinctAndAllowsCancellation() {
    let service = TestLoginItemService()
    service.registrationStatus = .requiresApproval
    let store = LaunchAtLoginStore(service: service)

    store.setEnabled(true)
    #expect(store.status == .requiresApproval)
    #expect(store.isRequested)
    store.setEnabled(false)
    #expect(store.status == .notRegistered)
    #expect(!store.isRequested)
    #expect(service.unregisterCount == 1)
}

@MainActor
@Test
func launchAtLoginShowsErrorsWithoutPretendingTheSettingChanged() {
    let service = TestLoginItemService()
    service.operationError = NSError(domain: "LoginItemTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration failed"])
    let store = LaunchAtLoginStore(service: service)

    store.setEnabled(true)
    #expect(!store.isRequested)
    #expect(store.errorMessage == "Registration failed")

    service.operationError = nil
    store.setEnabled(true)
    #expect(store.isRequested)
    #expect(store.errorMessage == nil)

    service.operationError = NSError(domain: "LoginItemTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unregistration failed"])
    store.setEnabled(false)
    #expect(store.isRequested)
    #expect(store.errorMessage == "Unregistration failed")
}

@MainActor
@Test
func launchAtLoginRefreshesChangesMadeInSystemSettings() {
    let service = TestLoginItemService()
    let store = LaunchAtLoginStore(service: service)

    service.status = .requiresApproval
    store.refresh()
    #expect(store.status == .requiresApproval)
    service.status = .enabled
    store.refresh()
    #expect(store.status == .enabled)
    service.status = .notRegistered
    store.refresh()
    #expect(!store.isRequested)

    // Recheck the system before a write so stale UI does not cause duplicate registration.
    service.status = .enabled
    store.setEnabled(true)
    #expect(service.registerCount == 0)
    #expect(store.isRequested)
}
