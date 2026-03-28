import FileProvider
import os.log

let logger = Logger(subsystem: "com.nimbus.app.FileProvider", category: "extension")

// @unchecked Sendable: domain and rclone are set at init and never mutated;
// NSFileProviderReplicatedExtension callbacks are dispatched by the File Provider
// daemon which owns the concurrency contract for this object.
class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension, @unchecked Sendable {

    let domain: NSFileProviderDomain
    private let rclone: RcloneClient

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        self.rclone = RcloneClient(remoteName: domain.identifier.rawValue)
        super.init()
        logger.info("FileProviderExtension initialized for domain: \(domain.identifier.rawValue)")
    }

    // MARK: - Lifecycle

    func invalidate() {
        logger.info("Extension invalidated for domain: \(self.domain.identifier.rawValue)")
    }

    // MARK: - Item Lookup

    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        if identifier == .rootContainer {
            completionHandler(FileProviderItem.rootContainer(domain: domain), nil)
        } else {
            // nonisolated(unsafe): completionHandler is an ObjC @escaping block;
            // the File Provider daemon guarantees its lifetime across the async hop.
            nonisolated(unsafe) let completionHandler = completionHandler
            Task {
                do {
                    let item = try await rclone.fetchItem(identifier: identifier)
                    completionHandler(item, nil)
                } catch {
                    logger.error("item(for:) failed: \(error.localizedDescription)")
                    completionHandler(nil, error)
                }
            }
        }
        return Progress()
    }

    // MARK: - Enumeration

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        logger.info("enumerator requested for: \(containerItemIdentifier.rawValue)")
        return FileProviderEnumerator(
            containerIdentifier: containerItemIdentifier,
            rclone: rclone,
            domain: domain
        )
    }

    // MARK: - Materialization (Download)

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        // nonisolated(unsafe): ObjC completion handler lifetime is guaranteed by the daemon.
        nonisolated(unsafe) let completionHandler = completionHandler

        Task {
            do {
                let (fileURL, item) = try await self.rclone.downloadFile(identifier: itemIdentifier)
                progress.completedUnitCount = 100
                completionHandler(fileURL, item, nil)
            } catch {
                logger.error("fetchContents failed: \(error.localizedDescription)")
                completionHandler(nil, nil, error)
            }
        }

        return progress
    }

    // MARK: - Upload (Create/Modify)

    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        // nonisolated(unsafe): ObjC types (completion handler, item template)
        // lifetime is guaranteed by the File Provider daemon across the async hop.
        nonisolated(unsafe) let completionHandler = completionHandler
        nonisolated(unsafe) let itemTemplate = itemTemplate

        Task {
            do {
                let item = try await rclone.createItem(basedOn: itemTemplate, contents: url)
                progress.completedUnitCount = 100
                completionHandler(item, [], false, nil)
            } catch {
                logger.error("createItem failed: \(error.localizedDescription)")
                completionHandler(nil, [], false, error)
            }
        }

        return progress
    }

    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        // nonisolated(unsafe): ObjC types (completion handler, item)
        // lifetime is guaranteed by the File Provider daemon across the async hop.
        nonisolated(unsafe) let completionHandler = completionHandler
        nonisolated(unsafe) let item = item

        Task {
            do {
                let updated = try await rclone.modifyItem(item, contents: newContents, changedFields: changedFields)
                progress.completedUnitCount = 100
                completionHandler(updated, [], false, nil)
            } catch {
                logger.error("modifyItem failed: \(error.localizedDescription)")
                completionHandler(nil, [], false, error)
            }
        }

        return progress
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        // nonisolated(unsafe): ObjC completion handler lifetime is guaranteed by the daemon.
        nonisolated(unsafe) let completionHandler = completionHandler
        Task {
            do {
                try await rclone.deleteItem(identifier: identifier)
                completionHandler(nil)
            } catch {
                logger.error("deleteItem failed: \(error.localizedDescription)")
                completionHandler(error)
            }
        }
        return Progress()
    }
}
