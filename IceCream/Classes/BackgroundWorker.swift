//
//  BackgroundWorker.swift
//  IceCream
//
//  Created by Kit Forge on 5/9/19.
//

import Foundation
import RealmSwift

// Based on https://academy.realm.io/posts/realm-notifications-on-background-threads-with-swift/
// Tweaked a little by Yue Cai

class BackgroundWorker: NSObject {
    
    static let shared = BackgroundWorker()
    
    private var thread: Thread?
    private var block:[(() -> Void)] = []
    private let lockObject = NSLock()
    
    func start(_ block: @escaping () -> Void) {
        lockObject.lock()
        self.block.append(block)
        lockObject.unlock()
        
        if thread == nil {
            thread = Thread { [weak self] in
                guard let self = self, let thread = self.thread else {
                    Thread.exit()
                    return
                }
                while !thread.isCancelled {
                    let t1 = Date()
                    RunLoop.current.run(
                        mode: .default,
                        before: Date.distantFuture)
                    
                    let t2 = Date()
                    let delta = t2.timeIntervalSince(t1)
                    if delta < 0.01 {
                        Thread.sleep(forTimeInterval: 0.02)
                    }
                }
                Thread.exit()
            }
            thread?.name = "\(String(describing: self))-\(UUID().uuidString)"
            thread?.start()
        }
        
        if let thread = thread {
            perform(#selector(runBlock),
                    on: thread,
                    with: nil,
                    waitUntilDone: true,
                    modes: [RunLoop.Mode.default.rawValue])
        }
    }
    
    func stop() {
        thread?.cancel()
    }
    
    @objc private func runBlock() {
        lockObject.lock()
        let blockArray = block
        block.removeAll()
        lockObject.unlock()
        for block in blockArray {
            block()
        }
    }
}
