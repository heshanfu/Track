//
//  Cache.swift
//  Demo
//
//  Created by 马权 on 5/17/16.
//  Copyright © 2016 马权. All rights reserved.
//

import Foundation

/**
 Cache async operation callback
 */
public typealias CacheAsyncCompletion = (cache: Cache?, key: String?, object: AnyObject?) -> Void

/**
 Track Cache Prefix, use on default disk cache folder name and queue name
 */
let TrackCachePrefix: String = "com.trackcache."

/**
 Track Cache default name, default disk cache folder name
 */
let TrackCacheDefauleName: String = "defauleTrackCache"

/**
 TrackCache is a thread safe cache, contain a thread safe memory cache and a thread safe diskcache
 */
public class Cache {
    
    /**
     cache name, used to create disk cache folder
     */
    public let name: String
    
    /**
     Thread safe memeory cache
     */
    public let memoryCache: MemoryCache
    
    /**
     Thread safe disk cache
     */
    public let diskCache: DiskCache
    
    private let _queue: dispatch_queue_t = dispatch_queue_create(TrackCachePrefix + (String(Cache)), DISPATCH_QUEUE_CONCURRENT)
    
    /**
     A share cache, contain a thread safe memory cache and a thread safe diskcache
     */
    public static let shareInstance = Cache(name: TrackCacheDefauleName)
    
    /**
     Design constructor
     The same name has the same diskCache, but different memorycache.
     
     - parameter name: cache name
     - parameter path: diskcache path
     */
    public init?(name: String, path: String) {
        if name.characters.count == 0 || path.characters.count == 0 {
            return nil
        }
        self.diskCache = DiskCache(name: name, path: path)!
        self.name = name
        self.memoryCache = MemoryCache.shareInstance
    }
    
    /**
     Convenience constructor, use default path Library/Caches/
     
     - parameter name: cache name
     */
    public convenience init?(name: String){
        self.init(name: name, path: NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true)[0])
    }
    
    
    //  MARK: Async
    
    /**
     Async store an object for the unique key in the memory cache and disk cache
     completion will be call after object has been store in memory cache and disk cache
     
     - parameter object:     object must be implement NSCoding protocal
     - parameter key:        unique key
     - parameter completion: stroe completion call back
     */
    public func set(object object: NSCoding, forKey key: String, completion: CacheAsyncCompletion?) {
        asyncGroup(2, operation: { completion in
            self.memoryCache.set(object: object, forKey: key) { _, _, _ in completion?() }
            self.diskCache.set(object: object, forKey: key) { _, _, _ in completion?() }
        }, notifyQueue: _queue) { [weak self] in
            guard let strongSelf = self else { completion?(cache: nil, key: nil, object: nil); return }
            completion?(cache: strongSelf, key: nil, object: nil)
        }
    }
    
    /**
     Async search object according to unique key
     search from memory cache first, if not found, will search from diskCache
     
     - parameter key:        object unique key
     - parameter completion: search completion call back
     */
    public func object(forKey key: String, completion: CacheAsyncCompletion?) {
        dispatch_async(_queue) { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.memoryCache.object(forKey: key) { [weak self] (memCache, memKey, memObject) in
                guard let strongSelf = self else { return }
                if memObject != nil {
                    dispatch_async(strongSelf._queue, {
                        completion?(cache: strongSelf, key: memKey, object: memObject)
                    })
                }
                else {
                    strongSelf.diskCache.object(forKey: key) { [weak self] (diskCache, diskKey, diskObject) in
                        guard let strongSelf = self else { return }
                        if let diskKey = diskKey, diskCache = diskCache {
                            strongSelf.memoryCache.set(object: diskCache, forKey: diskKey, completion: nil)
                        }
                        dispatch_async(strongSelf._queue, {
                            completion?(cache: strongSelf, key: diskKey, object: diskObject)
                        })
                    }
                }
            }
        }
    }
    
    /**
     Async remove object from memory cache and disk cache
     
     - parameter key:        object unique key
     - parameter completion: remove completion call back
     */
    public func removeObject(forKey key: String, completion: CacheAsyncCompletion?) {
        asyncGroup(2, operation: { completion in
            self.memoryCache.removeObject(forKey: key) { _, _, _ in completion?() }
            self.diskCache.removeObject(forKey: key) { _, _, _ in completion?() }
        }, notifyQueue: _queue) { [weak self] in
            guard let strongSelf = self else { completion?(cache: nil, key: nil, object: nil); return }
            completion?(cache: strongSelf, key: nil, object: nil)
        }
    }
    
    /**
     Async remove all objects
     
     - parameter completion: remove completion call back
     */
    public func removeAllObjects(completion: CacheAsyncCompletion?) {
        asyncGroup(2, operation: { completion in
            self.memoryCache.removeAllObjects { _, _, _ in completion?() }
            self.diskCache.removeAllObjects { _, _, _ in completion?() }
        }, notifyQueue: _queue) { [weak self] in
            guard let strongSelf = self else { completion?(cache: nil, key: nil, object: nil); return }
            completion?(cache: strongSelf, key: nil, object: nil)
        }
    }
    
    //  MARK: Sync
    
    /**
     Sync store an object for the unique key in the memory cache and disk cache
     
     - parameter object:     object must be implement NSCoding protocal
     - parameter key:        unique key
     - parameter completion: stroe completion call back
     */
    public func set(object object: NSCoding, forKey key: String) {
        memoryCache.set(object: object, forKey: key)
        diskCache.set(object: object, forKey: key)
    }
    
    /**
     Sync search an object according to unique key
     search from memory cache first, if not found, will search from diskCache
     
     - parameter key:        object unique key
     - parameter completion: search completion call back
     */
    public func object(forKey key: String) -> AnyObject? {
        if let object = memoryCache.object(forKey: key) {
            return object
        }
        else {
            if let object = diskCache.object(forKey: key) {
                memoryCache.set(object: object, forKey: key)
                return object
            }
        }
        return nil
    }
    
    /**
     Sync remove object from memory cache and disk cache
     
     - parameter key:        object unique key
     */
    public func removeObject(forKey key: String) {
        memoryCache.removeObject(forKey: key)
        diskCache.removeObject(forKey: key)
    }
    
    /**
     Sync remove all objects
     */
    public func removeAllObjects() {
        memoryCache.removeAllObjects()
        diskCache.removeAllObjects()
    }

    /**
     subscript method, sync set and get
     
     - parameter key: object unique key
     */
    public subscript(key: String) -> NSCoding? {
        get {
            if let returnValue = object(forKey: key) as? NSCoding {
                return returnValue
            }
            return nil
        }
        set {
            if let newValue = newValue {
                set(object: newValue, forKey: key)
            }
            else {
                removeObject(forKey: key)
            }
        }
    }
    
    //  MARK:
    //  MARK: Pirvate    
    private typealias OperationCompeltion = () -> Void
    
    private func asyncGroup(asyncNumber: Int,
                            operation: OperationCompeltion? -> Void,
                            notifyQueue: dispatch_queue_t,
                            completion: (() -> Void)?) {
        var group: dispatch_group_t? = nil
        var operationCompletion: OperationCompeltion?
        if (completion != nil) {
            group = dispatch_group_create()
            for _ in 0 ..< asyncNumber {
                group = dispatch_group_create()
            }
            operationCompletion = {
                dispatch_group_leave(group!)
            }
        }
        
        operation(operationCompletion)
        
        if let group = group {
            dispatch_group_notify(group, _queue) {
                completion?()
            }
        }
    }
}




