//
//  PublicDatabaseManager.swift
//  IceCream
//
//  Created by caiyue on 2019/4/22.
//
#if os(macOS)
import Cocoa
#else
import UIKit
#endif
import CloudKit
final class PublicDatabaseManager: DatabaseManager {
    
    let container: CKContainer
    let database: CKDatabase
    
    let syncObjects: [Syncable]
    
    init(objects: [Syncable], container: CKContainer) {
        self.syncObjects = objects
        self.container = container
        self.database = container.publicCloudDatabase
    }
    
    func fetchChangesInDatabase(_ callback: ((Error?) -> Void)?) {
        syncObjects.forEach { [weak self] syncObject in
            guard let self else { return }
            self.runQuery(recordType: syncObject.recordType, on: syncObject, callback: callback)
        }
    }
    
    func createCustomZonesIfAllowed() {
        
    }
    
    func createDatabaseSubscriptionIfHaveNot() {
        syncObjects.forEach { createSubscriptionInPublicDatabase(on: $0) }
    }
    
    func startObservingTermination() {
        #if os(iOS) || os(tvOS)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.cleanUp), name: UIApplication.willTerminateNotification, object: nil)
        
        #elseif os(macOS)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.cleanUp), name: NSApplication.willTerminateNotification, object: nil)
        
        #endif
    }
    
    func registerLocalDatabase() {
        syncObjects.forEach { object in
            DispatchQueue.main.async {
                object.registerLocalDatabase()
            }
        }
    }
    
    // MARK: - Private Methods
    private func runQuery(recordType: String,
                          on syncObject: Syncable,
                          cursor: CKQueryOperation.Cursor? = nil,
                          callback: ((Error?) -> Void)? = nil) {
        let operation: CKQueryOperation
        if let cursor = cursor {
            operation = CKQueryOperation(cursor: cursor)
        } else {
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: recordType, predicate: predicate)
            operation = CKQueryOperation(query: query)
        }
        // Optional tuning for background-friendly behavior
        operation.qualityOfService = .utility
        operation.resultsLimit = 150
        operation.recordFetchedBlock = { [weak self] record in
            guard let self = self else { return }
            autoreleasepool {
                let safe = self.threadSafeCopy(of: record)
                syncObject.add(record: safe)
            }
        }
        operation.queryCompletionBlock = { [weak self] nextCursor, error in
            guard let self = self else { return }
            switch ErrorHandler.shared.resultType(with: error) {
            case .success:
                if let nextCursor = nextCursor {
                    // Continue paging with a NEW operation
                    self.runQuery(recordType: recordType, on: syncObject, cursor: nextCursor, callback: callback)
                } else {
                    DispatchQueue.main.async { callback?(nil) }
                }
            case .retry(let timeToWait, _):
                // Never re-enqueue a finished operation; schedule a brand new one
                ErrorHandler.shared.retryOperationIfPossible(retryAfter: timeToWait) {
                    self.runQuery(recordType: recordType, on: syncObject, cursor: nextCursor, callback: callback)
                }
            default:
                break
            }
        }
        
        database.add(operation)
    }
    
    private func createSubscriptionInPublicDatabase(on syncObject: Syncable) {
        #if os(iOS) || os(tvOS) || os(macOS)
        let predict = NSPredicate(value: true)
        let subscription = CKQuerySubscription(
            recordType: syncObject.recordType,
            predicate: predict,
            subscriptionID: IceCreamSubscription.cloudKitPublicDatabaseSubscriptionID.id,
            options: [
                .firesOnRecordCreation,
                .firesOnRecordUpdate,
                .firesOnRecordDeletion
            ])
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent Push
        
        subscription.notificationInfo = notificationInfo
        
        let createOp = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
        createOp.modifySubscriptionsCompletionBlock = { _, _, _ in
            
        }
        createOp.qualityOfService = .utility
        database.add(createOp)
        #endif
    }
    
    @objc func cleanUp() {
        for syncObject in syncObjects {
            syncObject.cleanUp()
        }
    }
    
    private func threadSafeCopy(of record: CKRecord) -> CKRecord {
        let copy = CKRecord(recordType: record.recordType, recordID: record.recordID)
        for key in record.allKeys() {
            if let value = record[key] {
                copy[key] = value
            } else {
                copy[key] = nil
            }
        }
        return copy
    }
}
