import SwiftUI
import Foundation
import Firebase
import FirebaseStorage
import CoreBluetooth
import FirebaseFirestore
import FirebaseAuth

class PersonalModelsFunctions: ObservableObject {
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    
    func createCustomModelPlaceholder(
        for userEmail: String,
        named modelName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let storage = Storage.storage()
        let firestore = Firestore.firestore()
        
        
        let effectiveIdentifier: String
        if let email = Auth.auth().currentUser?.email {
            effectiveIdentifier = email
        } else if let uid = Auth.auth().currentUser?.uid {
            effectiveIdentifier = uid
        } else {
            completion(.failure(NSError(
                domain: "createCustomModelPlaceholder",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
            return
        }
        
        let folderRef = storage.reference().child("Users/\(effectiveIdentifier)/Models/\(modelName)/")
        let dummyFileRef = folderRef.child("dummy.txt")
        
        let dummyContent = "This is a dummy file."
        guard let data = dummyContent.data(using: .utf8) else {
            completion(.failure(NSError(domain: "DummyFile", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode dummy content"])))
            return
        }
        
        
        dummyFileRef.putData(data, metadata: nil) { metadata, error in
            if let error = error {
                
                completion(.failure(error))
                return
            } else {
                
            }
            
            guard
                let user = Auth.auth().currentUser,
                !user.isAnonymous
            else {
                completion(.failure(NSError(
                    domain: "Auth",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
                )))
                return
            }

            let currentUserUID = user.uid

            
            let userDocRef = firestore.collection("Users").document(currentUserUID)
            
            
            userDocRef.getDocument { snapshot, error in
                if let error = error {
                    
                    completion(.failure(error))
                    return
                }
                
                
                if snapshot?.exists == false {
                    userDocRef.setData([:]) { error in
                        if let error = error {
                            
                            completion(.failure(error))
                            return
                        } else {
                            
                        }
                        saveModelEntry()
                    }
                } else {
                    saveModelEntry()
                }
                
                
                
                func saveModelEntry() {
                    let formatter = DateFormatter()
                    formatter.calendar = Calendar(identifier: .iso8601)
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = "yy-MM-dd-HH-mm-ss"
                    
                    let nowString = formatter.string(from: Date())
                    
                    let modelData: [String: Any] = [
                        "description": "",
                        "keyword": "",
                        "creator": currentUserUID,
                        "rate": 0,
                        "creationData": nowString,
                        "publishDate": "",
                        "isFavourite": false,
                        "node": 0,
                    ]
                    
                    
                    userDocRef.setData([
                        "Models": [
                            modelName: modelData
                        ]
                    ], merge: true) { error in
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            completion(.success(()))
                        }
                    }
                    
                    
                }
            }
        }
    }
    
    func copyModelFolderToHistory(
        modelName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated."]
            )))
            return
        }


        let effectiveIdentifier: String
        if let email = user.email, !email.isEmpty {
            
            effectiveIdentifier = email
        } else {
            
            effectiveIdentifier = user.uid
        }


        let storage = Storage.storage()
        let srcRoot = storage.reference().child("Users/\(effectiveIdentifier)/Models/\(modelName)")
        let historyRoot = storage.reference().child("History/\(effectiveIdentifier)")

        let group = DispatchGroup()
        let lock = NSLock()
        var firstError: Error?

        func record(_ err: Error) {
            lock.lock(); defer { lock.unlock() }
            if firstError == nil { firstError = err }
        }

        
        func resolveUniqueHistoryName(baseName: String, completion: @escaping (String) -> Void) {
            historyRoot.listAll { result, err in
                
                guard err == nil, let result = result else {
                    completion(baseName)
                    return
                }
                let existing: Set<String> = Set(result.prefixes.map { $0.name }) 

                if !existing.contains(baseName) {
                    completion(baseName)
                    return
                }
                var n = 1
                var candidate = "\(n)\(baseName)"
                while existing.contains(candidate) {
                    n += 1
                    candidate = "\(n)\(baseName)"
                }
                completion(candidate)
            }
        }

        
        func copyThenDeleteFile(src: StorageReference, dst: StorageReference) {
            group.enter()
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

            let downloadTask = src.write(toFile: tmpURL) { _, dlErr in
                if let dlErr = dlErr {
                    record(dlErr)
                    group.leave()
                    return
                }

                dst.putFile(from: tmpURL, metadata: nil) { _, upErr in
                    
                    try? FileManager.default.removeItem(at: tmpURL)

                    if let upErr = upErr {
                        record(upErr)
                        group.leave()
                        return
                    }

                    src.delete { delErr in
                        if let delErr = delErr { record(delErr) }
                        group.leave()
                    }
                }
            }

            downloadTask.observe(.failure) { snap in
                if let err = snap.error { record(err) }
            }
        }

        func copyFolder(src: StorageReference, dst: StorageReference) {
            group.enter()
            src.listAll { result, err in
                defer { group.leave() }

                if let err = err {
                    record(err)
                    return
                }
                guard let result = result else { return }

                
                for item in result.items {
                    let dstItem = dst.child(item.name)
                    copyThenDeleteFile(src: item, dst: dstItem)
                }

                
                for prefix in result.prefixes {
                    let dstPrefix = dst.child(prefix.name)
                    copyFolder(src: prefix, dst: dstPrefix)
                }
            }
        }

        
        resolveUniqueHistoryName(baseName: modelName) { uniqueName in
            let dstRoot = historyRoot.child(uniqueName)

            
            copyFolder(src: srcRoot, dst: dstRoot)

            group.notify(queue: .main) {
                if let err = firstError {
                    completion(.failure(err))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    func deleteModel(
        modelName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let firestore = Firestore.firestore()
        
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
            return
        }

        let uid = user.uid

        let userDocRef = firestore.collection("Users").document(uid)
        let batch = firestore.batch()
        
        
        let nestedPath = FieldPath(["Models", modelName])
        batch.updateData([nestedPath: FieldValue.delete()], forDocument: userDocRef)
        
        
        batch.updateData([modelName: FieldValue.delete()], forDocument: userDocRef)
        
        batch.commit { error in
            if let error = error {
                
                completion(.failure(error))
            } else {
                self.copyModelFolderToHistory(modelName: modelName) { result in
                    switch result {
                    case .success:
                        print("")
                    case .failure(let error):
                        print("")
                    }
                }
                completion(.success(()))
            }
        }
    }
    
    func modelExistsInFirestore(
        modelName: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        let firestore = Firestore.firestore()
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.success(false))
            return
        }

        let uid = user.uid

        
        let userDocRef = firestore.collection("Users").document(uid)
        
        userDocRef.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let snap = snapshot, snap.exists else {
                completion(.success(false))
                return
            }
            
            
            let fp = FieldPath(["Models", modelName])
            if let _ = snap.get(fp) as? [String: Any] {
                completion(.success(true))
                return
            }
            
            
            if let _ = snap.data()?[modelName] as? [String: Any] {
                completion(.success(true))
                return
            }
            
            completion(.success(false))
        }
    }
    func fetchAllFavouriteModels(
        completion: @escaping (Result<[String: Model], Error>) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
            return
        }

        let uid = user.uid
        let firestore = Firestore.firestore()

        let userRef = firestore
            .collection("Users")
            .document(uid)

        let rateRef = firestore
            .collection("Published")
            .document("en")

        let group = DispatchGroup()

        var favsAny: [String: Any] = [:]
        var rateModels: [String: Any] = [:]
        var fetchError: Error?

        // Fetch user favourites
        group.enter()
        userRef.getDocument { snapshot, error in
            defer { group.leave() }
            if let error = error {
                fetchError = error
                return
            }
            favsAny = snapshot?.data()?["FavouriteModels"] as? [String: Any] ?? [:]
        }

        // Fetch rates from EN
        group.enter()
        rateRef.getDocument { snapshot, error in
            defer { group.leave() }
            if let error = error {
                fetchError = error
                return
            }
            rateModels = snapshot?.data()?["models"] as? [String: Any] ?? [:]
        }

        group.notify(queue: .main) {
            if let error = fetchError {
                completion(.failure(error))
                return
            }

            var result: [String: Model] = [:]

            for (name, value) in favsAny {
                guard let dict = value as? [String: Any] else { continue }

                let description = dict["description"] as? String ?? ""
                let keyword = dict["keyword"] as? String ?? ""
                let creator = dict["creator"] as? String ?? ""
                let publishDate = dict["publishDate"] as? String ?? ""
                let createdWithVib = dict["createdWithVib"] as? Bool ?? false

                // 🔑 RATE — ALWAYS FROM Published/en
                let rateDict = rateModels[name] as? [String: Any]
                let rate = (rateDict?["rate"] as? Int)
                    ?? Int(rateDict?["rate"] as? String ?? "0")
                    ?? 0

                let creationDate =
                    (dict["creationData"] as? String)
                    ?? (dict["creationDate"] as? String)
                    ?? ""

                let justCreated = dict["justCreated"] as? Bool ?? false

                let model = Model(
                    name: name,
                    description: description,
                    keyword: keyword,
                    creator: creator,
                    rate: rate,
                    creationDate: creationDate,
                    publishDate: publishDate,
                    justCreated: justCreated,
                    createdWithVib: createdWithVib
                )

                result[name] = model
            }

            completion(.success(result))
        }
    }

    func upsertFavouriteModel(
        named modelName: String,
        creator: String,
        createdAt: String,
        description: String,
        taps: [Int: [Int: [TapEntry]]],
        commandNames: [Int: [Int: String]],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let storage = Storage.storage()
        let firestore = Firestore.firestore()
        
        guard
            let user = Auth.auth().currentUser,
            let uid = user.uid as String?,
            let email = user.email
        else {
            completion(.failure(NSError(domain: "Auth", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        
        let effectiveIdentifier: String
        if let email = Auth.auth().currentUser?.email, !email.isEmpty {
            
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        {
            let uid = user.uid

            
            effectiveIdentifier = uid
        } else {
            completion(.failure(NSError(
                domain: "Auth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated."]
            )))
            return
        }

        let safeModel = modelName.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        
        
        let baseRef      = storage.reference().child("Users").child(effectiveIdentifier).child("FavouriteModels").child(safeModel)
        let dataFileRef  = baseRef.child("ModelData.json")
        let namesFileRef = baseRef.child("ModelNames.json")
        let imageFileRef = baseRef.child("ModelImage.jpg")

        
        
        
        let userDocRef = firestore.collection("Users").document(uid)
        
        
        let tapsDict = taps.reduce(into: [String: [String: [[String: Any]]]]()) { result, outer in
            let (outerKey, innerDict) = outer
            result["\(outerKey)"] = innerDict.reduce(into: [String: [[String: Any]]]()) { innerRes, inner in
                let (innerKey, entries) = inner
                innerRes["\(innerKey)"] = entries.map { e in
                    ["key": e.key, "entryType": e.entryType, "id": e.id.uuidString,
                     "modelName": e.modelName, "value": e.value, "groupId": e.groupId]
                }
            }
        }
        let namesDict: [String: [String: String]] = commandNames.reduce(into: [:]) { dict, outer in
            dict["\(outer.key)"] = outer.value.reduce(into: [:]) { $0["\($1.key)"] = $1.value }
        }
        
        func json(_ obj: Any) throws -> Data {
            try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        }
        
        
        let df = DateFormatter()
        df.calendar = .init(identifier: .iso8601)
        df.locale = .init(identifier: "en_US_POSIX")
        df.timeZone = .init(secondsFromGMT: 0)
        df.dateFormat = "yy-MM-dd-HH-mm-ss"
        
        let modelData: [String: Any] = [
            "description": description, "keyword": "", "creator": creator,
            "rate": 0, "creationData": createdAt,
            "publishDate": createdAt, "isFavourite": true, "node": 0
        ]
        
        
        let group = DispatchGroup()
        var firstError: Error?
        
        let meta = StorageMetadata()
        meta.contentType = "application/json"
        
        do {
            let tapsData = try json(tapsDict)
            group.enter()
            dataFileRef.putData(tapsData, metadata: meta) { md, err in
                if let err = err {
                    
                    if firstError == nil { firstError = err }
                } else {
                    
                    dataFileRef.downloadURL { url, e in
                        
                    }
                }
                group.leave()
            }
        } catch {
            completion(.failure(error)); return
        }
        
        do {
            let namesData = try json(namesDict)
            group.enter()
            namesFileRef.putData(namesData, metadata: meta) { md, err in
                if let err = err {
                    
                    if firstError == nil { firstError = err }
                } else {
                    
                    namesFileRef.downloadURL { url, e in
                        
                    }
                }
                group.leave()
            }
        } catch {
            completion(.failure(error)); return
        }
        
        group.enter()
        let originalImageRef = storage.reference()
            .child("Users")
            .child(effectiveIdentifier)   // same identifier you used above
            .child("Models")
            .child(safeModel)
            .child("ModelImage.jpg")

        originalImageRef.getData(maxSize: 5 * 1024 * 1024) { data, err in
            if let err = err as NSError? {
                if err.domain == StorageErrorDomain,
                   StorageErrorCode(rawValue: err.code) == .objectNotFound {
                    // no image set, skip silently
                    print("ℹ️ No image for \(safeModel)")
                } else if firstError == nil {
                    firstError = err
                }
                group.leave()
                return
            }
            if let data = data {
                let pngMeta = StorageMetadata()
                pngMeta.contentType = "image/jpg"
                imageFileRef.putData(data, metadata: pngMeta) { _, putErr in
                    if let putErr = putErr, firstError == nil { firstError = putErr }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }

        
        group.notify(queue: .main) {
            if let e = firstError {
                completion(.failure(e))
                return
            }
            
            
            baseRef.listAll { result, e in
                if let e = e {
                    
                } else {
                    
                }
            }
            
            
            userDocRef.setData([
                "FavouriteModels": [ safeModel: modelData ]
            ], merge: true) { setError in
                if let setError = setError {
                    completion(.failure(setError))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    func deleteFavouriteModel(
        named modelName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let storage = Storage.storage()
        let firestore = Firestore.firestore()
        
        guard
            let user = Auth.auth().currentUser,
            let uid = user.uid as String?,
            let email = user.email
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
            return
        }
        let effectiveIdentifier: String
        if let email = Auth.auth().currentUser?.email, !email.isEmpty {
            
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        {
            let uid = user.uid

            
            effectiveIdentifier = uid
        } else {
            completion(.failure(NSError(
                domain: "Auth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated."]
            )))
            return
        }

        let safeModel = modelName.replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        
        let baseRef = storage.reference()
            .child("Users").child(effectiveIdentifier)
            .child("FavouriteModels").child(safeModel)
        
        let userDocRef = firestore.collection("Users").document(uid)
        
        
        func deleteAll(at ref: StorageReference, completion: @escaping (Error?) -> Void) {
            ref.listAll { result, error in
                if let error = error { completion(error); return }
                
                let group = DispatchGroup()
                var firstError: Error?
                
                result?.items.forEach { item in
                    group.enter()
                    item.delete { err in
                        if firstError == nil { firstError = err }
                        group.leave()
                    }
                }
                result?.prefixes.forEach { prefix in
                    group.enter()
                    deleteAll(at: prefix) { err in
                        if firstError == nil { firstError = err }
                        group.leave()
                    }
                }
                group.notify(queue: .main) { completion(firstError) }
            }
        }
        
        
        deleteAll(at: baseRef) { storageError in
            if let storageError = storageError {
                completion(.failure(storageError))
                return
            }
            
            
            let fp = FieldPath(["FavouriteModels", safeModel])
            userDocRef.updateData([fp: FieldValue.delete()]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    func appendDataForCustomModel(
        for userEmail: String,
        named modelName: String,
        taps: [Int: [Int: [TapEntry]]],
        commandNames: [Int: [Int: String]],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let storage = Storage.storage()
        let effectiveIdentifier: String
        if let email = Auth.auth().currentUser?.email, !email.isEmpty {
            
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        {
            let uid = user.uid

            
            effectiveIdentifier = uid
        } else {
            completion(.failure(NSError(
                domain: "Auth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated."]
            )))
            return
        }

        let folderRef   = storage.reference().child("Users/\(effectiveIdentifier)/Models/\(modelName)/")
        let tapsFileRef = folderRef.child("ModelData.json")
        let namesFileRef = folderRef.child("ModelNames.json")
        
        
        let tapsDictionary = taps.reduce(into: [String: [String: [[String: Any]]]]()) { result, outerPair in
            let (outerKey, innerDict) = outerPair
            result["\(outerKey)"] = innerDict.reduce(into: [String: [[String: Any]]]()) { innerResult, innerPair in
                let (innerKey, tapEntries) = innerPair
                innerResult["\(innerKey)"] = tapEntries.map { entry in
                    [
                        "key": entry.key,
                        "entryType": entry.entryType,
                        "id": entry.id.uuidString,
                        "modelName": entry.modelName,
                        "value": entry.value,
                        "groupId": entry.groupId
                    ]
                }
            }
        }
        
        
        let namesDictionary: [String: [String: String]] = commandNames.reduce(into: [:]) { dict, outer in
            let (outerKey, inner) = outer
            dict["\(outerKey)"] = inner.reduce(into: [:]) { innerDict, pair in
                innerDict["\(pair.key)"] = pair.value
            }
        }
        
        func data(from object: Any) throws -> Data {
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        }
        
        let group = DispatchGroup()
        var firstError: Error?
        
        
        do {
            let tapsData = try data(from: tapsDictionary)
            group.enter()
            tapsFileRef.putData(tapsData, metadata: nil) { _, error in
                if let error = error, firstError == nil { firstError = error }
                group.leave()
            }
        } catch {
            completion(.failure(error))
            return
        }
        
        
        do {
            let namesData = try data(from: namesDictionary)
            group.enter()
            namesFileRef.putData(namesData, metadata: nil) { _, error in
                if let error = error, firstError == nil { firstError = error }
                group.leave()
            }
        } catch {
            completion(.failure(error))
            return
        }
        
        group.notify(queue: .main) {
            if let error = firstError {
                
                completion(.failure(error))
            } else {
                
                completion(.success(()))
            }
        }
    }
    
    func fetchMyModels(for userEmail: String, completion: @escaping (Result<[String], Error>) -> Void) {
        let storage = Storage.storage()
        
        
        let effectiveIdentifier: String
        if let email = Auth.auth().currentUser?.email, !email.isEmpty {
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        {
            let uid = user.uid

            effectiveIdentifier = uid
        } else {
            completion(.failure(NSError(
                domain: "Auth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated."]
            )))
            return
        }

        
        let modelsRef = storage.reference().child("Users/\(effectiveIdentifier)/Models")
        
        modelsRef.listAll { result, error in
            if let error = error {
                
                completion(.failure(error))
                return
            }

            
            guard let result = result else {
                
                completion(.failure(NSError(
                    domain: "FirebaseStorage",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "No models found."]
                )))
                return
            }

            let folderNames = result.prefixes.map { $0.name }
            completion(.success(folderNames))
        }

    }

    func fetchModelData(
        for modelName: String,
        uid: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let firestore = Firestore.firestore()
        
        let userDocRef = firestore.collection("Users").document(uid)
        
        userDocRef.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let doc = snapshot, doc.exists else {
                completion(.failure(NSError(
                    domain: "Firestore", code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "User document not found."]
                )))
                return
            }
            
            
            let fp = FieldPath(["Models", modelName])
            if let modelData = doc.get(fp) as? [String: Any] {
                completion(.success(modelData))
                return
            }
            
            
            if let legacy = doc.data()?[modelName] as? [String: Any] {
                completion(.success(legacy))
                return
            }
            
            completion(.failure(NSError(
                domain: "Firestore", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Model '\(modelName)' not found."]
            )))
        }
    }
    
    func fetchConfigForMyModel(
        userEmail: String,
        modelName: String,
        completion: @escaping (Result<(taps: [Int: [Int: [TapEntry]]], names: [Int: [Int: String]]), Error>) -> Void
    ) {
        let storage = Storage.storage()
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated."]
            )))
            return
        }


        
        let effectiveIdentifier: String
        if !userEmail.isEmpty {
            effectiveIdentifier = userEmail
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            effectiveIdentifier = user.uid
        }
        
        let folder = storage.reference().child("Users/\(effectiveIdentifier)/Models/\(modelName)")
        
        let tapsRef  = folder.child("ModelData.json")
        let namesRef = folder.child("ModelNames.json")
        
        let group = DispatchGroup()
        var firstError: Error?
        
        var fetchedTaps   = [Int: [Int: [TapEntry]]]()
        var fetchedNames  = [Int: [Int: String]]()
        
        
        func mapKeysToInt<T>(_ dict: [String: [String: T]]) -> [Int: [Int: T]] {
            var out: [Int: [Int: T]] = [:]
            for (k, inner) in dict {
                guard let ok = Int(k) else { continue }
                var innerOut: [Int: T] = [:]
                for (ik, v) in inner {
                    if let iik = Int(ik) { innerOut[iik] = v }
                }
                out[ok] = innerOut
            }
            return out
        }
        
        
        group.enter()
        tapsRef.getData(maxSize: 5 * 1024 * 1024) { data, error in
            defer { group.leave() }
            if let error = error {
                firstError = firstError ?? error
                
                return
            }
            guard let data = data else {
                let err = NSError(domain: "FetchError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data for ModelData.json"])
                firstError = firstError ?? err
                return
            }
            
            do {
                
                let raw = try JSONDecoder().decode([String: [String: [TapEntry]]].self, from: data)
                fetchedTaps = mapKeysToInt(raw)
            } catch {
                firstError = firstError ?? error
                
            }
        }
        
        
        group.enter()
        namesRef.getData(maxSize: 5 * 1024 * 1024) { data, error in
            defer { group.leave() }
            if let error = error {
                
                
                return
            }
            guard let data = data else { return }
            
            do {
                let raw = try JSONDecoder().decode([String: [String: String]].self, from: data)
                fetchedNames = mapKeysToInt(raw)
            } catch {
                
                
            }
        }
        
        group.notify(queue: .main) {
            if let error = firstError {
                completion(.failure(error))
            } else {
                completion(.success((taps: fetchedTaps, names: fetchedNames)))
            }
        }
    }
    
    func updateModelDescription(
        modelName: String,
        to newText: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
            return
        }

        let uid = user.uid

        
        let userDoc = Firestore.firestore()
            .collection("Users")
            .document(uid)
        
        
        let fieldPath = FieldPath(["Models", modelName, "description"])
        
        userDoc.updateData([fieldPath: newText]) { error in
            if let error = error {
                
                completion(.failure(error))
            } else {
                
                completion(.success(()))
            }
        }
    }
    
    func deleteAccount(completion: @escaping (Bool) -> Void) {
        let firestore = Firestore.firestore()

        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            completion(false)
            return
        }

        let effectiveIdentifier: String
        if let email = user.email, !email.isEmpty {
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            effectiveIdentifier = user.uid
        }

        let uid = user.uid

        let group = DispatchGroup()
        let lock = NSLock()
        var firstError: Error?

        func record(_ err: Error) {
            lock.lock(); defer { lock.unlock() }
            if firstError == nil { firstError = err }
        }

        let storage = Storage.storage()

        // ---- move/delete "Users/<effectiveIdentifier>/Models" (as you had) ----
        group.enter()
        let modelsRoot = storage.reference().child("Users/\(effectiveIdentifier)/Models")
        modelsRoot.listAll { result, err in
            defer { group.leave() }
            if let err = err { record(err); return }
            guard let result = result else { return }

            for prefix in result.prefixes {
                group.enter()
                self.copyModelFolderToHistory(modelName: prefix.name) { moveResult in
                    if case .failure(let e) = moveResult { record(e) }
                    group.leave()
                }
            }

            for file in result.items {
                group.enter()
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let dst = storage.reference().child("History/\(effectiveIdentifier)/\(file.name)/\(file.name)")
                file.write(toFile: tmpURL) { _, dlErr in
                    if let dlErr = dlErr { record(dlErr); group.leave(); return }
                    dst.putFile(from: tmpURL, metadata: nil) { _, upErr in
                        try? FileManager.default.removeItem(at: tmpURL)
                        if let upErr = upErr { record(upErr); group.leave(); return }
                        file.delete { delErr in
                            if let delErr = delErr { record(delErr) }
                            group.leave()
                        }
                    }
                }
            }
        }

        // ---- delete Firestore docs (as you had) ----
        group.enter()
        firestore.collection("Users").document(uid).delete { err in
            if let err = err { record(err) }
            group.leave()
        }

        group.enter()
        let followerDocRef = firestore.collection("Followers").document(uid)
        let tokensRef = followerDocRef.collection("deviceTokens")
        deleteCollection(tokensRef, batchSize: 50) { subErr in
            if let subErr = subErr { record(subErr) }
            followerDocRef.delete { err in
                if let err = err { record(err) }
                group.leave()
            }
        }

        // ---- generic recursive deleter (unchanged logic) ----
        func deleteFolderRecursively(_ folder: StorageReference) {
            group.enter()
            folder.listAll { result, err in
                defer { group.leave() }
                if let err = err { record(err); return }
                guard let result = result else { return }

                // delete files in this "folder"
                for file in result.items {
                    group.enter()
                    file.delete { delErr in
                        if let delErr = delErr { record(delErr) }
                        group.leave()
                    }
                }

                // recurse into subfolders
                for prefix in result.prefixes {
                    deleteFolderRecursively(prefix)
                }
            }
        }

        // ---- delete Users/<effectiveIdentifier>/ (as before) ----
        deleteFolderRecursively(storage.reference().child("Users/\(effectiveIdentifier)"))

        // **** NEW: fully delete ProfileImages/<uid>/ and its contents ****
        deleteFolderRecursively(storage.reference().child("ProfileImages/\(uid)"))

        // ---- finish ----
        group.notify(queue: .main) {
            completion(firstError == nil)
        }
    }

    
    func deleteCollection(_ collection: CollectionReference,
                          batchSize: Int = 50,
                          completion: @escaping (Error?) -> Void) {
        func batchDelete() {
            collection.limit(to: batchSize).getDocuments { snap, err in
                if let err = err { completion(err); return }
                guard let snap = snap, !snap.isEmpty else { completion(nil); return }

                let batch = collection.firestore.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }

                batch.commit { commitErr in
                    if let commitErr = commitErr { completion(commitErr); return }
                    
                    batchDelete()
                }
            }
        }
        batchDelete()
    }
}






