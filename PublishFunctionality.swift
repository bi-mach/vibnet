//
//  PublishFunctionality.swift
//  Vibro
//
//  Created by lyubcsenko on 12/08/2025.
//
import SwiftUI
import Foundation
import Firebase
import FirebaseStorage
import CoreBluetooth
import FirebaseFirestore
import FirebaseAuth
import NaturalLanguage
private func currentAppLanguage() -> String {
    Bundle.main.preferredLocalizations.first ?? "en"
}


extension StorageReference {
    func putDataAsync(_ data: Data, metadata: StorageMetadata?) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { cont in
            self.putData(data, metadata: metadata) { meta, err in
                if let err = err { cont.resume(throwing: err) }
                else { cont.resume(returning: meta ?? StorageMetadata()) }
            }
        }
    }
}

class PublishFunctionality: ObservableObject {
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    func fetchAllPublishedModels(
        completion: @escaping (Result<[String: Model], Error>) -> Void
    ) {
        let language = currentAppLanguage()
        let firestore = Firestore.firestore()

        let localizedRef = firestore
            .collection("Published")
            .document(language)

        let rateRef = firestore
            .collection("Published")
            .document("en")

        // Fetch both documents in parallel
        let group = DispatchGroup()

        var localizedModels: [String: Any] = [:]
        var rateModels: [String: Any] = [:]
        var fetchError: Error?

        group.enter()
        localizedRef.getDocument { snapshot, error in
            defer { group.leave() }
            if let error = error {
                fetchError = error
                return
            }
            localizedModels = snapshot?.data()?["models"] as? [String: Any] ?? [:]
        }

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

            for (name, value) in localizedModels {
                guard let dict = value as? [String: Any] else { continue }

                let description   = dict["description"] as? String ?? ""
                let creator       = dict["creator"] as? String ?? ""
                let publishDate   = dict["publishDate"] as? String ?? ""
                let createdWithVib = dict["createdWithVib"] as? Bool ?? false

                // 🔑 RATE — ALWAYS FROM EN
                let rateDict = rateModels[name] as? [String: Any]
                let rate = (rateDict?["rate"] as? Int)
                    ?? Int(rateDict?["rate"] as? String ?? "0")
                    ?? 0

                // Defaults (Firestore does not provide these)
                let keyword = ""
                let creationDate = ""
                let justCreated = false

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

    func fetchModelInReview(completion: @escaping (Result<([String: Date], Bool), Error>) -> Void) {
        guard
            let currentUser = Auth.auth().currentUser,
            !currentUser.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
            return
        }


        let uid = currentUser.uid
        let firestore = Firestore.firestore()
        let userDocRef = firestore.collection("ModelsInReview").document(uid)
        let modelsRef = userDocRef.collection("models")

        // Step 1️⃣: Fetch parent document to get successfulReview
        userDocRef.getDocument { userDocSnapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let successfulReview = userDocSnapshot?.data()?["successfulReview"] as? Bool ?? false

            // Step 2️⃣: Fetch models from the subcollection
            modelsRef.order(by: "publishDate", descending: true).getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    // ✅ No models but still return correct successfulReview value
                    completion(.success(([:], successfulReview)))
                    return
                }

                var models: [String: Date] = [:]

                for doc in documents {
                    let data = doc.data()
                    let name = doc.documentID

                    // Parse publishDate
                    var publishDate = Date()
                    if let timestamp = data["publishDate"] as? Timestamp {
                        publishDate = timestamp.dateValue()
                    } else if let dateString = data["publishDate"] as? String {
                        let formatter = DateFormatter()
                        formatter.calendar = Calendar(identifier: .iso8601)
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        formatter.timeZone = TimeZone(secondsFromGMT: 0)
                        formatter.dateFormat = "yy-MM-dd-HH-mm-ss"
                        if let parsedDate = formatter.date(from: dateString) {
                            publishDate = parsedDate
                        }
                    }

                    models[name] = publishDate
                }

                completion(.success((models, successfulReview)))
            }
        }
    }

    func fetchBlockedUsers(
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        // 1) Auth check
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
        }

        let currentUID = user.uid

        
        // 2) Reference to current user’s document
        let db = Firestore.firestore()
        let userRef = db.collection("Followers").document(currentUID)
        
        // 3) Fetch the document
        userRef.getDocument { document, error in
            if let error = error {
                return completion(.failure(error))
            }
            
            guard let document = document, document.exists else {
                return completion(.success([])) // No doc → no blocked users
            }
            
            // 4) Extract the array safely
            let blocked = document.get("Blocked_Users") as? [String] ?? []
            completion(.success(blocked))
        }
    }

    func blockUser(
        userToBlockUID: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // 1) Auth check
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
        }

        let currentUID = user.uid

        
        // 2) Prevent blocking self
        guard currentUID != userToBlockUID else {
            return completion(.failure(NSError(
                domain: "Validation",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "You cannot block yourself"]
            )))
        }
        
        // 3) Reference to current user’s document
        let db = Firestore.firestore()
        let userRef = db.collection("Followers").document(currentUID)
        
        // 4) Add to Blocked_Users array using arrayUnion
        userRef.updateData([
            "Blocked_Users": FieldValue.arrayUnion([userToBlockUID])
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    
    func unblockUser(
        userToUnblockUID: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // 1) Auth check
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
        }

        let currentUID = user.uid

        
        // 2) Prevent trying to unblock yourself
        guard currentUID != userToUnblockUID else {
            return completion(.failure(NSError(
                domain: "Validation",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "You cannot unblock yourself"]
            )))
        }
        
        // 3) Reference to current user’s document
        let db = Firestore.firestore()
        let userRef = db.collection("Followers").document(currentUID)
        
        // 4) Remove from Blocked_Users array using arrayRemove
        userRef.updateData([
            "Blocked_Users": FieldValue.arrayRemove([userToUnblockUID])
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    
    func deleteModelsFromReview(modelName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
        }


        let effectiveIdentifier: String
        if let email = user.email, !email.isEmpty {
            // Sanitize email for safe Firebase paths
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Fallback to UID if email is missing or hidden (Apple Sign-In)
            effectiveIdentifier = user.uid
        }

        let uid = user.uid
        let email = user.email ?? ""
        let storage = Storage.storage()
        let db = Firestore.firestore()
        let language = currentAppLanguage()
        let fromRoot = storage.reference().child("PublishedModels/\(language)/\(modelName)")
        let toRoot   = storage.reference().child("Users/\(effectiveIdentifier)/Models")

        // 1) Move all objects in Storage
        moveFolderRecursively(from: fromRoot, to: toRoot) { moveResult in
            switch moveResult {
            case .failure(let err):
                completion(.failure(err))

            case .success:
                // 2) After move, list destination folders to infer model names
                toRoot.listAll { result, listErr in
                    if let listErr = listErr {
                        completion(.failure(listErr))
                        return
                    }

                    // Each subfolder name is treated as a model name
                    let modelNames = result?.prefixes.map { $0.name } ?? []

                    // 3) For each model, write an entry under Users/{uid}
                    let group = DispatchGroup()
                    var firstError: Error?

                    for modelName in modelNames {
                        group.enter()
                        self.saveModelEntry(db: db, uid: uid, modelName: modelName) { writeResult in
                            if case .failure(let e) = writeResult, firstError == nil {
                                firstError = e
                            }
                            group.leave()
                        }
                    }

                    group.notify(queue: .main) {
                        if let err = firstError {
                            completion(.failure(err))
                            return
                        }

                        // 4) Delete Firestore subcollection /ModelsInReview/{uid}/models/* then parent doc
                        self.deleteModelsInReviewFirestore(uid: uid, db: db) { deleteResult in
                            switch deleteResult {
                            case .failure(let err):
                                completion(.failure(err))
                            case .success:
                                completion(.success(()))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Writes a single model entry under Users/{uid}.Models.{modelName}
    private func saveModelEntry(db: Firestore,
                                uid: String,
                                modelName: String,
                                completion: @escaping (Result<Void, Error>) -> Void) {
        // Match your requested timestamp format in UTC
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yy-MM-dd-HH-mm-ss"
        
        let nowString = formatter.string(from: Date())
        
        let modelData: [String: Any] = [
            "description": "",
            "keyword": "",
            "creator": uid,
            "rate": 0,
            "creationData": nowString,
            "publishDate": "",
            "isFavourite": false,
            "node": 0,
        ]
        
        let userDocRef = db.collection("Users").document(uid)
        
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


    // MARK: - Storage moving
    private func moveFolderRecursively(from src: StorageReference,
                                       to dst: StorageReference,
                                       completion: @escaping (Result<Void, Error>) -> Void) {
        src.listAll { listResult, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let listResult = listResult else {
                completion(.success(()))
                return
            }

            let group = DispatchGroup()
            var firstError: Error?

            // Recurse into subfolders (prefixes)
            for prefix in listResult.prefixes {
                let childDst = dst.child(prefix.name)
                group.enter()
                self.moveFolderRecursively(from: prefix, to: childDst) { result in
                    if case .failure(let e) = result, firstError == nil { firstError = e }
                    group.leave()
                }
            }

            // Move each file (item)
            for item in listResult.items {
                let destItem = dst.child(item.name)
                group.enter()
                self.moveSingleObject(from: item, to: destItem) { result in
                    if case .failure(let e) = result, firstError == nil { firstError = e }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if let err = firstError { completion(.failure(err)) } else { completion(.success(())) }
            }
        }
    }

    private func moveSingleObject(from src: StorageReference,
                                  to dst: StorageReference,
                                  completion: @escaping (Result<Void, Error>) -> Void) {
        // Fetch metadata to preserve contentType & custom metadata
        src.getMetadata { meta, metaErr in
            if let metaErr = metaErr {
                completion(.failure(metaErr))
                return
            }

            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)

            // Download to local temp file
            let downloadTask = src.write(toFile: tempURL) { url, dlErr in
                if let dlErr = dlErr {
                    completion(.failure(dlErr))
                    return
                }

                // Prepare metadata
                let newMeta = StorageMetadata()
                newMeta.contentType = meta?.contentType
                if let custom = meta?.customMetadata { newMeta.customMetadata = custom }

                // Upload to destination
                let uploadTask = dst.putFile(from: tempURL, metadata: newMeta) { _, upErr in
                    // Clean temp file
                    try? FileManager.default.removeItem(at: tempURL)

                    if let upErr = upErr {
                        completion(.failure(upErr))
                        return
                    }

                    // Delete original
                    src.delete { delErr in
                        if let delErr = delErr {
                            completion(.failure(delErr))
                        } else {
                            completion(.success(()))
                        }
                    }
                }

                // Optional: observe progress / pause / resume via `uploadTask` if you like
                _ = uploadTask
            }

            // Optional: observe progress via `downloadTask`
            _ = downloadTask
        }
    }

    // MARK: - Firestore deleting

    /// Deletes all docs in /ModelsInReview/{uid}/models and then deletes /ModelsInReview/{uid}
    private func deleteModelsInReviewFirestore(uid: String,
                                               db: Firestore,
                                               completion: @escaping (Result<Void, Error>) -> Void) {
        let parent = db.collection("ModelsInReview").document(uid)
        let models = parent.collection("models")

        models.getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error)); return
            }

            let docs = snapshot?.documents ?? []
            let chunkSize = 450 // stay well under 500 batch limit
            let chunks: [[QueryDocumentSnapshot]] = stride(from: 0, to: docs.count, by: chunkSize).map {
                Array(docs[$0..<min($0+chunkSize, docs.count)])
            }

            func deleteNextChunk(_ idx: Int) {
                guard idx < chunks.count else {
                    // After subcollection docs are deleted, delete parent doc
                    parent.delete { parentErr in
                        if let parentErr = parentErr { completion(.failure(parentErr)) }
                        else { completion(.success(())) }
                    }
                    return
                }

                let batch = db.batch()
                for d in chunks[idx] { batch.deleteDocument(d.reference) }
                batch.commit { batchErr in
                    if let batchErr = batchErr { completion(.failure(batchErr)) }
                    else { deleteNextChunk(idx + 1) }
                }
            }

            deleteNextChunk(0)
        }
    }
    func sendModelToReview(
        named modelName: String,
        publishName: String,
        publishDescription: String,
        taps: [Int: [Int: [TapEntry]]],
        commandNames: [Int: [Int: String]],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let storage   = Storage.storage()
        let firestore = Firestore.firestore()

        guard
            let currentUser = Auth.auth().currentUser,
            !currentUser.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated or email missing"]
            )))
            return
        }

        let uid = currentUser.uid

        // STORAGE paths
        let folderRef    = storage.reference().child("ModelsInReview/\(uid)/\(publishName)/")
        let dummyFileRef = folderRef.child("dummy.txt")
        let namesFileRef = folderRef.child("CommandNames.json")
        let tapsFileRef  = folderRef.child("ModelData.json")

        let jsonMeta = StorageMetadata(); jsonMeta.contentType = "application/json"
        let txtMeta  = StorageMetadata(); txtMeta.contentType  = "text/plain"

        // Encode JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let namesData: Data
        let tapsData: Data
        do {
            namesData = try encoder.encode(commandNames)
            tapsData  = try encoder.encode(taps)
        } catch {
            completion(.failure(error))
            return
        }
        
        

        // 1) (Optional) Upload dummy first
        let dummyContent = Data("This is a dummy file.".utf8)
        dummyFileRef.putData(dummyContent, metadata: txtMeta) { _, error in
            if let error = error {
                print("[ERROR] Failed to upload dummy.txt: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            // 2) Parallel tasks: names.json, taps.json, Firestore doc
            let group = DispatchGroup()
            var firstError: Error?

            // names.json
            group.enter()
            namesFileRef.putData(namesData, metadata: jsonMeta) { _, err in
                if let err = err, firstError == nil { firstError = err }
                group.leave()
            }

            // ModelData.json
            group.enter()
            tapsFileRef.putData(tapsData, metadata: jsonMeta) { _, err in
                if let err = err, firstError == nil { firstError = err }
                group.leave()
            }

            // Firestore doc at /ModelsInReview/{uid}/models/{publishName}
            let modelDocRef = firestore
                .collection("ModelsInReview")
                .document(uid)
                .collection("models")
                .document(publishName)

            // Prefer a server timestamp; if you want to keep the string, retain your formatter
            let modelDoc: [String: Any] = [
                "description": publishDescription,
                "creator": uid,
                "rate": 0,
                "publishDate": FieldValue.serverTimestamp()
            ]

            group.enter() // <-- only once for this task
            modelDocRef.setData(modelDoc, merge: true) { err in
                if let err = err, firstError == nil { firstError = err }
                group.leave()
            }

            group.notify(queue: .main) { [weak self] in
                if let err = firstError {
                    completion(.failure(err))
                } else {
                    // Optional cleanup
                    self?.deleteModelFromUserStorageAndFirestore(modelName: modelName) { delResult in
                        switch delResult {
                        case .success:
                            completion(.success(()))
                        case .failure(let e):
                            print("❌ Delete failed:", e.localizedDescription)
                            completion(.success(())) // still succeed overall
                        }
                    }
                }
            }
        }
    }



    func increaseModelRate(
        publishName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        func currentAppLanguage() -> String {
            Bundle.main.preferredLocalizations.first ?? "en"
        }
        let language = currentAppLanguage()
        let firestore = Firestore.firestore()
        let rootDocRef = firestore.collection("Published").document("en")
        
        // Use FieldValue.increment to atomically increase the rate by 1
        let path = "models.\(publishName).rate"
        
        rootDocRef.updateData([
            path: FieldValue.increment(Int64(1))
        ]) { error in
            if let error = error {
                print("❌ Failed to increase rate: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("✅ Successfully increased rate for \(publishName)")
                completion(.success(()))
            }
        }
    }
    func decreaseModelRate(
        publishName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        func currentAppLanguage() -> String {
            Bundle.main.preferredLocalizations.first ?? "en"
        }
        let language = currentAppLanguage()
        let firestore = Firestore.firestore()
        let rootDocRef = firestore.collection("Published").document("en")
        
        // Use FieldValue.increment with -1 to atomically decrease the rate by 1
        let path = "models.\(publishName).rate"
        
        rootDocRef.updateData([
            path: FieldValue.increment(Int64(-1))
        ]) { error in
            if let error = error {
                print("❌ Failed to decrease rate: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("✅ Successfully decreased rate for \(publishName)")
                completion(.success(()))
            }
        }
    }

    
    
    
    
    private func callAddNewModel(modelName: String,
                                 completion: @escaping (Result<Void, Error>) -> Void) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No signed-in user"]
            )))
            return
        }

        user.getIDTokenForcingRefresh(true) { idToken, tokenErr in
            if let tokenErr = tokenErr {
                completion(.failure(tokenErr)); return
            }
            guard
                let idToken = idToken,
                let url = URL(string: "https://nodes-functionality-one-1047255165048.europe-central2.run.app/add_new_model")
            else {
                completion(.failure(NSError(domain: "CloudRun", code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: "Bad URL or token"])))
                return
            }

            struct RequestBody: Encodable { let ModelName: String }
            let body = RequestBody(ModelName: modelName)

            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            do { req.httpBody = try JSONEncoder().encode(body) } catch {
                completion(.failure(error)); return
            }

            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err { completion(.failure(err)); return }
                let http = resp as? HTTPURLResponse
                let status = http?.statusCode ?? -1
                let msg = String(data: data ?? Data(), encoding: .utf8) ?? ""

                guard (200...299).contains(status) else {
                    completion(.failure(NSError(domain: "CloudRun",
                                                code: status,
                                                userInfo: [NSLocalizedDescriptionKey: msg])))
                    return
                }
                
                
                
                completion(.success(()))
            }.resume()
        }
    }
    
    
    func notifyAboutNewModel(
        recepient_uid: String,
        author_uid: String,
        model_name: String,
        author_name: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No signed-in user"]
            )))
            return
        }


        user.getIDTokenForcingRefresh(true) { idToken, tokenErr in
            if let tokenErr = tokenErr {
                completion(.failure(tokenErr))
                return
            }

            guard
                let idToken = idToken,
                let url = URL(string: "https://nodes-functionality-one-1047255165048.europe-central2.run.app/notify_user_about_following_new_model_route")
            else {
                completion(.failure(NSError(
                    domain: "CloudRun",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Bad URL or token"]
                )))
                return
            }
            let currentLanguage = Locale.current.language.languageCode?.identifier
                ?? Locale.preferredLanguages.first?.prefix(2).lowercased()
                ?? "en"  // fallback to English
            
            // 🔹 Updated request body with all fields
            struct RequestBody: Encodable {
                let recipient_uid: String
                let author_uid: String
                let model_name: String
                let author_name: String
                let language: String
            }

            let body = RequestBody(
                recipient_uid: recepient_uid,
                author_uid: author_uid,
                model_name: model_name,
                author_name: author_name,
                language: currentLanguage
            )

            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

            do {
                req.httpBody = try JSONEncoder().encode(body)
            } catch {
                completion(.failure(error))
                return
            }

            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err {
                    completion(.failure(err))
                    return
                }

                let http = resp as? HTTPURLResponse
                let status = http?.statusCode ?? -1
                let msg = String(data: data ?? Data(), encoding: .utf8) ?? ""

                guard (200...299).contains(status) else {
                    completion(.failure(NSError(
                        domain: "CloudRun",
                        code: status,
                        userInfo: [NSLocalizedDescriptionKey: msg]
                    )))
                    return
                }

                completion(.success(()))
            }.resume()
        }
    }
    /// Recursively deletes a Storage folder (all items and subfolders).
    private func recursiveDeleteREVIEWStorageFolder(_ ref: StorageReference, completion: @escaping (Error?) -> Void) {
        ref.listAll { list, err in
            if let err = err {
                completion(err); return
            }
            guard let list = list else {
                completion(NSError(domain: "Storage", code: -100, userInfo: [NSLocalizedDescriptionKey: "listAll returned nil"]))
                return
            }

            let group = DispatchGroup()
            var firstErr: Error?

            // Delete files
            for item in list.items {
                group.enter()
                item.delete { err in
                    if let err = err, firstErr == nil { firstErr = err }
                    group.leave()
                }
            }

            // Recurse into subfolders
            for prefix in list.prefixes {
                group.enter()
                self.recursiveDeleteREVIEWStorageFolder(prefix) { err in
                    if let err = err, firstErr == nil { firstErr = err }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion(firstErr)
            }
        }
    }

    /// Deletes Firestore data in ModelsInReview.
    /// If `modelName` is provided, deletes /ModelsInReview/{uid}/models/{modelName},
    /// then tries to delete parent if subcollection is now empty.
    /// If `modelName` is nil, deletes ALL docs under models/ then the parent doc.
    private func deleteModeFROMReviewFirestore(uid: String, modelName: String?, completion: @escaping (Error?) -> Void) {
        let db = Firestore.firestore()
        let parent = db.collection("ModelsInReview").document(uid)
        let models = parent.collection("models")

        func deleteParentIfEmpty(_ done: @escaping (Error?) -> Void) {
            models.limit(to: 1).getDocuments { snap, err in
                if let err = err { done(err); return }
                if let snap = snap, snap.documents.isEmpty {
                    parent.delete(completion: done) // delete the /ModelsInReview/{uid} doc
                } else {
                    done(nil) // models still exist; keep parent
                }
            }
        }

        // Delete specific model only
        if let name = modelName {
            models.document(name).delete { err in
                if let err = err { completion(err); return }
                deleteParentIfEmpty(completion)
            }
            return
        }

        // Delete ALL model docs then parent doc
        models.getDocuments { snap, err in
            if let err = err { completion(err); return }
            guard let snap = snap else {
                completion(NSError(domain: "Firestore", code: -101, userInfo: [NSLocalizedDescriptionKey: "No snapshot"]))
                return
            }

            let batch = db.batch()
            for d in snap.documents { batch.deleteDocument(d.reference) }
            batch.commit { err in
                if let err = err { completion(err); return }
                parent.delete(completion: completion)
            }
        }
    }

    
    
    
    
    
    
    
    func notifyFollowersAboutNewPost(
        recepient_uid: String,
        author_uid: String,
        post_id: String,
        post_title: String,
        post_content: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No signed-in user"]
            )))
            return
        }


        let currentLanguage = Locale.current.language.languageCode?.identifier
            ?? Locale.preferredLanguages.first?.prefix(2).lowercased()
            ?? "en"  // fallback to English
        
        user.getIDTokenForcingRefresh(true) { idToken, tokenErr in
            if let tokenErr = tokenErr {
                completion(.failure(tokenErr))
                return
            }

            guard
                let idToken = idToken,
                let url = URL(string: "https://nodes-functionality-one-1047255165048.europe-central2.run.app/notify_followers_about_new_post")
            else {
                completion(.failure(NSError(
                    domain: "CloudRun",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Bad URL or token"]
                )))
                return
            }

            // 🔹 Updated request body with all fields
            struct RequestBody: Encodable {
                let recipient_uid: String
                let author_uid: String
                let post_id: String
                let post_title: String
                let post_content: String
                let language: String   // <-- Added field
            }

            let body = RequestBody(
                recipient_uid: recepient_uid,
                author_uid: author_uid,
                post_id: post_id,
                post_title: post_title,
                post_content: post_content,
                language: currentLanguage
            )

            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

            do {
                req.httpBody = try JSONEncoder().encode(body)
            } catch {
                completion(.failure(error))
                return
            }

            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err {
                    completion(.failure(err))
                    return
                }

                let http = resp as? HTTPURLResponse
                let status = http?.statusCode ?? -1
                let msg = String(data: data ?? Data(), encoding: .utf8) ?? ""

                guard (200...299).contains(status) else {
                    completion(.failure(NSError(
                        domain: "CloudRun",
                        code: status,
                        userInfo: [NSLocalizedDescriptionKey: msg]
                    )))
                    return
                }

                completion(.success(()))
            }.resume()
        }
    }
    
    func notifyFollowerThatIfollow(
        recepient_uid: String,
        author_uid: String,
        author_name: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No signed-in user"]
            )))
            return
        }

        
        

        user.getIDTokenForcingRefresh(true) { idToken, tokenErr in
            if let tokenErr = tokenErr {
                completion(.failure(tokenErr))
                return
            }

            guard
                let idToken = idToken,
                let url = URL(string: "https://nodes-functionality-one-1047255165048.europe-central2.run.app/notify_new_friend_route")
            else {
                completion(.failure(NSError(
                    domain: "CloudRun",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Bad URL or token"]
                )))
                return
            }
            let currentLanguage = Locale.current.language.languageCode?.identifier
                ?? Locale.preferredLanguages.first?.prefix(2).lowercased()
                ?? "en"  // fallback to English
            // 🔹 Updated request body with all fields
            struct RequestBody: Encodable {
                let recipient_uid: String
                let author_uid: String
                let author_name: String
                let language: String
            }

            let body = RequestBody(
                recipient_uid: recepient_uid,
                author_uid: author_uid,
                author_name: author_name,
                language: currentLanguage
            )

            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

            do {
                req.httpBody = try JSONEncoder().encode(body)
            } catch {
                completion(.failure(error))
                return
            }

            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err {
                    completion(.failure(err))
                    return
                }

                let http = resp as? HTTPURLResponse
                let status = http?.statusCode ?? -1
                let msg = String(data: data ?? Data(), encoding: .utf8) ?? ""

                guard (200...299).contains(status) else {
                    completion(.failure(NSError(
                        domain: "CloudRun",
                        code: status,
                        userInfo: [NSLocalizedDescriptionKey: msg]
                    )))
                    return
                }

                completion(.success(()))
            }.resume()
        }
    }

    func notifyAboutLikingModel(
        recepient_uid: String,
        author_uid: String,
        model_name: String,
        author_name: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No signed-in user"]
            )))
            return
        }

        user.getIDTokenForcingRefresh(true) { idToken, tokenErr in
            if let tokenErr = tokenErr {
                completion(.failure(tokenErr))
                return
            }

            guard
                let idToken = idToken,
                let url = URL(string: "https://nodes-functionality-one-1047255165048.europe-central2.run.app/notify_user_about_their_model_added_to_fav_route")
            else {
                completion(.failure(NSError(
                    domain: "CloudRun",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Bad URL or token"]
                )))
                return
            }
            let currentLanguage = Locale.current.language.languageCode?.identifier
                ?? Locale.preferredLanguages.first?.prefix(2).lowercased()
                ?? "en"  // fallback to English
            // 🔹 Updated request body with all fields
            struct RequestBody: Encodable {
                let recipient_uid: String
                let author_uid: String
                let model_name: String
                let author_name: String
                let language: String
            }

            let body = RequestBody(
                recipient_uid: recepient_uid,
                author_uid: author_uid,
                model_name: model_name,
                author_name: author_name,
                language: currentLanguage
            )

            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

            do {
                req.httpBody = try JSONEncoder().encode(body)
            } catch {
                completion(.failure(error))
                return
            }

            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err {
                    completion(.failure(err))
                    return
                }

                let http = resp as? HTTPURLResponse
                let status = http?.statusCode ?? -1
                let msg = String(data: data ?? Data(), encoding: .utf8) ?? ""

                guard (200...299).contains(status) else {
                    completion(.failure(NSError(
                        domain: "CloudRun",
                        code: status,
                        userInfo: [NSLocalizedDescriptionKey: msg]
                    )))
                    return
                }

                completion(.success(()))
            }.resume()
        }
    }
    
    private func deleteFolder(_ ref: StorageReference, completion: @escaping (Error?) -> Void) {
        ref.listAll { result, error in
            if let error = error { completion(error); return }
            
            let group = DispatchGroup()
            var firstError: Error?
            
            // delete all files
            result?.items.forEach { item in
                group.enter()
                item.delete { err in
                    if let err = err, firstError == nil { firstError = err }
                    group.leave()
                }
            }
            
            // recurse into subfolders
            result?.prefixes.forEach { subref in
                group.enter()
                self.deleteFolder(subref) { err in
                    if let err = err, firstError == nil { firstError = err }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) { completion(firstError) }
        }
    }
    /// Delete Storage folder and Firestore map entry for the model.
    func deleteModelFromUserStorageAndFirestore(
        modelName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No signed-in user"]
            )))
            return
        }

        let uid = user.uid
        
        let effectiveIdentifier: String
        if let email = user.email, !email.isEmpty {
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let providerEmail = user.providerData.compactMap({ $0.email }).first, !providerEmail.isEmpty {
            effectiveIdentifier = providerEmail
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Fallback to UID if no email is available (e.g., Sign in with Apple with Hide My Email)
            effectiveIdentifier = user.uid
        }
        let storage = Storage.storage()
        let firestore = Firestore.firestore()
        
        let userModelFolder = storage.reference()
            .child("Users/\(effectiveIdentifier)/Models/\(modelName)")
        
        let userDocRef = firestore.collection("Users").document(uid)
        let modelsFieldPath = FieldPath(["Models", modelName])
        
        let group = DispatchGroup()
        var firstError: Error?
        
        // 1) Delete Storage folder (recursive)
        group.enter()
        self.deleteFolder(userModelFolder) { err in
            if let err = err, firstError == nil { firstError = err }
            group.leave()
        }
        
        // 2) Delete Firestore nested map entry: Users/{uid}.Models.<modelName>
        group.enter()
        userDocRef.updateData([modelsFieldPath: FieldValue.delete()]) { err in
            if let err = err, firstError == nil { firstError = err }
            group.leave()
        }
        
        group.notify(queue: .main) {
            if let err = firstError {
                completion(.failure(err))
            } else {
                completion(.success(()))
            }
        }
    }
    
    
    private func currentAppLanguage() -> String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    func fetchConfigForPublishedModel(
        modelName: String,
        completion: @escaping (Result<(taps: [Int: [Int: [TapEntry]]], names: [Int: [Int: String]]), Error>) -> Void
    ) {
        let language = currentAppLanguage()
        let storage = Storage.storage()
        let folder = storage.reference().child("PublishedModels/\(language)/\(modelName)")
        
        let tapsRef  = folder.child("ModelData.json")
        let namesRef = folder.child("CommandNames.json")
        
        let group = DispatchGroup()
        var firstError: Error?
        
        var fetchedTaps   = [Int: [Int: [TapEntry]]]()
        var fetchedNames  = [Int: [Int: String]]()
        
        // Helper: convert [String: [String: T]] -> [Int: [Int: T]]
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
        
        // 1) Fetch ModelData.json
        group.enter()
        tapsRef.getData(maxSize: 5 * 1024 * 1024) { data, error in
            defer { group.leave() }
            if let error = error {
                firstError = firstError ?? error
                print("[ERROR] Failed to fetch ModelData.json: \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                let err = NSError(domain: "FetchError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data for ModelData.json"])
                firstError = firstError ?? err
                return
            }
            
            do {
                // Decode with string keys, then map to Int keys.
                let raw = try JSONDecoder().decode([String: [String: [TapEntry]]].self, from: data)
                fetchedTaps = mapKeysToInt(raw)
            } catch {
                firstError = firstError ?? error
                print("[ERROR] Decode ModelData.json failed: \(error.localizedDescription)")
            }
        }
        
        // 2) Fetch ModelNames.json (if missing, treat as empty)
        group.enter()
        namesRef.getData(maxSize: 5 * 1024 * 1024) { data, error in
            defer { group.leave() }
            if let error = error {
                // If file is missing or any error, default to empty names (don’t fail whole fetch)
                print("[WARN] Couldn’t fetch ModelNames.json (defaulting to empty): \(error.localizedDescription)")
                return
            }
            guard let data = data else { return }
            
            do {
                let raw = try JSONDecoder().decode([String: [String: String]].self, from: data)
                fetchedNames = mapKeysToInt(raw)
            } catch {
                // If names fail to decode, keep empty; don’t fail whole fetch.
                print("[WARN] Decode ModelNames.json failed (defaulting to empty): \(error.localizedDescription)")
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
    
    
    func fetchValidIDToken(completion: @escaping (String?) -> Void) {
        Auth.auth().signInAnonymously { authResult, error in
            if let error = error {
                completion(nil)
                return
            }
            guard let user = authResult?.user else {
                completion(nil)
                return
            }
            self.fetchToken(for: user, completion: completion)
        }
    }
    func fetchToken(for user: User, completion: @escaping (String?) -> Void) {
        user.getIDTokenResult(forcingRefresh: false) { tokenResult, error in
            if let error = error {
                completion(nil)
                return
            }
            
            guard let tokenResult = tokenResult else {
                completion(nil)
                return
            }
            
            let expirationDate = tokenResult.expirationDate
            let bufferDate = Date().addingTimeInterval(300)
            if expirationDate < bufferDate {
                user.getIDTokenResult(forcingRefresh: true) { refreshedTokenResult, error in
                    if let error = error {
                        completion(nil)
                        return
                    }
                    guard let refreshedToken = refreshedTokenResult?.token else {
                        completion(nil)
                        return
                    }
                    completion(refreshedToken)
                }
            } else {
                completion(tokenResult.token)
            }
        }
    }
    
    func addNewModelToNodes(modelName: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            self.fetchValidIDToken { token in
                guard let token = token else {
                    print("[addNewModelToNodes] Failed to retrieve token.")
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                // TODO: replace with your real endpoint for creating nodes
                guard let url = URL(string: "https://your-service.example.com/nodes") else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                // Build JSON body for the new node/model
                let payload: [String: Any] = [
                    "ModelName": modelName
                ]

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
                } catch {
                    print("[addNewModelToNodes] Failed to encode JSON: \(error)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        print("[addNewModelToNodes] Request error: \(error)")
                        DispatchQueue.main.async { completion(false) }
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("[addNewModelToNodes] No HTTPURLResponse.")
                        DispatchQueue.main.async { completion(false) }
                        return
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        print("[addNewModelToNodes] HTTP \(httpResponse.statusCode)")
                        // Optionally log response body for debugging
                        if let data = data, let body = String(data: data, encoding: .utf8) {
                            print("[addNewModelToNodes] Body: \(body)")
                        }
                        DispatchQueue.main.async { completion(false) }
                        return
                    }

                    // Optionally parse response JSON if you need the created node back
                    // e.g., let node = try? JSONDecoder().decode(Node.self, from: data)

                    DispatchQueue.main.async { completion(true) }
                }.resume()
            }
        }
    }

    /*
     Task {
         do {
             try await signInAnonymouslyIfNeeded()

             // 🔑 Always read from sharedData (source of truth)
             guard let storedModel = sharedData.publishedModels[model.name] else {
                 return
             }

             let text = storedModel.description

             // 1️⃣ Heuristic gate
             guard shouldTranslate(text) else {
                 displayedText = text
                 return
             }

             let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

             let targetLanguage =
                 Locale.current.language.languageCode?.identifier ?? "en"

             // 2️⃣ Native iOS language detection
             let recognizer = NLLanguageRecognizer()
             recognizer.processString(trimmed)

             let detectedLanguage =
                 recognizer.dominantLanguage?.rawValue

             // 3️⃣ Already in app language → use stored value
             guard detectedLanguage != targetLanguage else {
                 displayedText = text
                 return
             }

             let result = try await translateApi.translate(
                 text: trimmed,
                 targetLanguage: targetLanguage
             )

             await MainActor.run {
                 displayedText = result.translatedText

                 var updated = storedModel
                 updated.description = result.translatedText
                 sharedData.publishedModels[model.name] = updated
             }

         } catch {
             print("Translate error:", error.localizedDescription)
         }
     }

     
     Task {
         do {
             try await signInAnonymouslyIfNeeded()

             let targetLanguage =
                 Locale.current.language.languageCode?.identifier ?? "en"

             let snapshot = payload.names

             // Full map: ALWAYS filled (translated or original)
             var out: [Int: [Int: String]] = [:]

             for (groupId, commands) in snapshot {
                 var groupOut: [Int: String] = [:]

                 for (commandId, name) in commands {
                     let finalText = try await translateOrKeepOriginal(
                         name,
                         targetLanguage: targetLanguage,
                         translateApi: translateApi
                     )
                     groupOut[commandId] = finalText
                 }

                 out[groupId] = groupOut
             }

             await MainActor.run {
                 withAnimation(.easeInOut(duration: 0.35)) {
                     commandNames = out
                 }
                 sharedData.translatedCommandNames[model.name] = out
             }

         } catch {
             commandNames = payload.names
             print("Translate error:", error.localizedDescription)
         }
     }
 */
    
    private struct PublishRequest: Codable {
        let modelName: String
        let publishName: String
        let publishDescription: String
        let commandNames: [Int: [Int: String]]
        let taps: [Int: [Int: [TapEntry]]]
        let sourceLanguageCode: String?
        let cleanupUserModel: Bool
    }

    private struct PublishResponse: Codable {
        let success: Bool
        let publishName: String?
        let publishDate: String?
        let languages: [String]?
        let error: String?
    }

    private func callPublishAPI(
        modelName: String,
        publishName: String,
        publishDescription: String,
        commandNames: [Int: [Int: String]],
        taps: [Int: [Int: [TapEntry]]],
        sourceLanguageCode: String? = nil,
        cleanupUserModel: Bool = true
    ) async throws {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No signed-in user"])
        }

        let idToken = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            user.getIDToken { token, err in
                if let err = err { cont.resume(throwing: err) }
                else if let token = token { cont.resume(returning: token) }
                else {
                    cont.resume(throwing: NSError(
                        domain: "Auth",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Missing ID token"]
                    ))
                }
            }
        }

        // 🔁 Change this to your Cloud Run URL
        let baseURL = "https://translate-api-1047255165048.europe-west1.run.app"
        guard let url = URL(string: "\(baseURL)/publish") else {
            throw NSError(domain: "URL", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bad publish URL"])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let body = PublishRequest(
            modelName: modelName,
            publishName: publishName,
            publishDescription: publishDescription,
            commandNames: commandNames,
            taps: taps,
            sourceLanguageCode: sourceLanguageCode,
            cleanupUserModel: cleanupUserModel
        )

        let encoder = JSONEncoder()
        req.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse

        // If server returns non-JSON error body, show it
        if http?.statusCode ?? 500 >= 400 {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "PublishAPI", code: http?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "Publish API failed (\(http?.statusCode ?? 0)): \(text)"])
        }

        // Parse JSON response (optional but useful)
        let decoded = try? JSONDecoder().decode(PublishResponse.self, from: data)
        if decoded?.success != true {
            throw NSError(domain: "PublishAPI", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: decoded?.error ?? "Publish failed"])
        }
    }



    func publishModel(
        named modelName: String,
        publishName: String,
        publishDescription: String,
        taps: [Int: [Int: [TapEntry]]],
        commandNames: [Int: [Int: String]],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task {
            do {
                // Optional: tell server what language your base text is
                let sourceLang = Bundle.main.preferredLocalizations.first

                try await self.callPublishAPI(
                    modelName: modelName,
                    publishName: publishName,
                    publishDescription: publishDescription,
                    commandNames: commandNames,
                    taps: taps,
                    sourceLanguageCode: sourceLang,   // server will still translate to English etc.
                    cleanupUserModel: true            // server handles cleanup
                )

                // ✅ SUCCESS
                await MainActor.run {
                    callAddNewModel(modelName: modelName) { result in
                        switch result {
                        case .success:
                            print("Model added successfully")
                        case .failure(let error):
                            print("Failed:", error)
                        }
                    }

                    completion(.success(()))
                }

            } catch {
                // ❌ FAILURE
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }


    private func translateOrKeepOriginal(
        _ text: String,
        targetLanguage: String,
        translateApi: TranslateAPI
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        // Your heuristic gate
        guard shouldTranslate(trimmed) else { return text }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let detected = recognizer.dominantLanguage?.rawValue

        // already in target language
        if detected == targetLanguage { return text }

        let result = try await translateApi.translate(
            text: trimmed,
            targetLanguage: targetLanguage
        )
        return result.translatedText
    }

    private func translateCommandNames(
        _ input: [Int: [Int: String]],
        targetLanguage: String,
        translateApi: TranslateAPI
    ) async throws -> [Int: [Int: String]] {
        var out: [Int: [Int: String]] = [:]

        for (groupId, commands) in input {
            var groupOut: [Int: String] = [:]

            for (commandId, name) in commands {
                let translated = try await translateOrKeepOriginal(
                    name,
                    targetLanguage: targetLanguage,
                    translateApi: translateApi
                )
                groupOut[commandId] = translated
            }

            out[groupId] = groupOut
        }

        return out
    }
    func shouldTranslate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return false }
        guard trimmed.count >= 3 else { return false }
        guard trimmed.range(of: #"\p{L}"#, options: .regularExpression) != nil else {
            return false
        }

        return true
    }


    private func translateAndSaveToAllLanguages(
        publishName: String,
        creatorUid: String,
        basePublishDate: String,
        baseDescription: String,
        baseCommandNames: [Int: [Int: String]],
        tapsData: Data,
        modelImageData: Data?,              // optional
        storageRoot: String = "PublishedModels",
        translateApi: TranslateAPI
    ) async throws {

        let firestore = Firestore.firestore()
        let storage = Storage.storage()

        // All languages from app localizations
        // (filters out "Base")
        let languages = Bundle.main.localizations.filter { $0 != "Base" }
        // If you want to ensure base language exists:
        // let languages = Array(Set(Bundle.main.localizations.filter { $0 != "Base" }))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonMeta = StorageMetadata()
        jsonMeta.contentType = "application/json"

        let txtMeta = StorageMetadata()
        txtMeta.contentType = "text/plain"

        let imgMeta = StorageMetadata()
        imgMeta.contentType = "image/jpg"

        // Prepare Firestore constant fields
        // (Keep your same structure; we’re just extending it with commandNames per language)
        for lang in languages {
            // 1) Translate
            let translatedDescription = try await translateOrKeepOriginal(
                baseDescription,
                targetLanguage: lang,
                translateApi: translateApi
            )
            
            let translatedCommandNames = try await translateCommandNames(
                baseCommandNames,
                targetLanguage: lang,
                translateApi: translateApi
            )
            
            // 2) Storage folder: PublishedModels/<lang>/<publishName>/
            let folderRef = storage.reference().child("\(storageRoot)/\(lang)/\(publishName)/")
            let namesFileRef = folderRef.child("CommandNames.json")
            let tapsFileRef  = folderRef.child("ModelData.json")
            
            // Optional: also store translated description as a file
            let descFileRef  = folderRef.child("Description.txt")
            
            // Encode translated command names
            let namesData = try encoder.encode(translatedCommandNames)
            
            // Upload translated assets
            _ = try await namesFileRef.putDataAsync(namesData, metadata: jsonMeta)
            _ = try await tapsFileRef.putDataAsync(tapsData, metadata: jsonMeta)
            
            // Optional description file
            if let descData = translatedDescription.data(using: .utf8) {
                _ = try await descFileRef.putDataAsync(descData, metadata: txtMeta)
            }
            
            // Optional image copy (same image to all languages)
            if let modelImageData {
                let modelImageRef = folderRef.child("ModelImage.jpg")
                _ = try await modelImageRef.putDataAsync(modelImageData, metadata: imgMeta)
            }
            
            // 3) Firestore: Published/<lang> doc, models.<publishName>.{description,commandNames,...}
            let docRef = firestore.collection("Published").document(lang)
            
            // Use FieldPath so publishName with dots won’t break
            let modelRoot = FieldPath(["models", publishName])
            
            // We can setData merge to create doc if missing
            // but FieldPath can't be used as keys in setData with nested maps easily.
            // So: write the whole nested map using standard dictionary shape.
            let payload: [String: Any] = [
                "models": [
                    publishName: [
                        "description": translatedDescription,
                        "creator": creatorUid,
                        "rate": 0,
                        "publishDate": basePublishDate
                    ]
                ]
            ]

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                docRef.setData(payload, merge: true) { err in
                    if let err = err {
                        cont.resume(throwing: err)
                    } else {
                        cont.resume(returning: ())
                    }
                }
            }
        }
    }



    
    private func callDeleteNewModel(modelName: String,
                                 completion: @escaping (Result<Void, Error>) -> Void) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No signed-in user"]
            )))
            return
        }


        user.getIDTokenForcingRefresh(true) { idToken, tokenErr in
            if let tokenErr = tokenErr {
                completion(.failure(tokenErr)); return
            }
            guard
                let idToken = idToken,
                let url = URL(string: "https://nodes-functionality-one-1047255165048.europe-central2.run.app/delete_new_model")
            else {
                completion(.failure(NSError(domain: "CloudRun", code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: "Bad URL or token"])))
                return
            }

            struct RequestBody: Encodable { let ModelName: String }
            let body = RequestBody(ModelName: modelName)

            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            do { req.httpBody = try JSONEncoder().encode(body) } catch {
                completion(.failure(error)); return
            }

            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err { completion(.failure(err)); return }
                let http = resp as? HTTPURLResponse
                let status = http?.statusCode ?? -1
                let msg = String(data: data ?? Data(), encoding: .utf8) ?? ""

                guard (200...299).contains(status) else {
                    completion(.failure(NSError(domain: "CloudRun",
                                                code: status,
                                                userInfo: [NSLocalizedDescriptionKey: msg])))
                    return
                }
                
                
                
                completion(.success(()))
            }.resume()
        }
    }
    
    private struct DeletePublishedRequest: Codable {
        let modelName: String
        let storageRoot: String
    }

    private struct DeletePublishedResponse: Codable {
        let success: Bool
        let error: String?
    }

    private func callDeleteModelFromPublishedAPI(
        modelName: String,
        storageRoot: String
    ) async throws {

        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            throw NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No signed-in user"]
            )
        }
        let idToken: String = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<String, Error>) in

            user.getIDToken { token, err in
                if let err = err {
                    cont.resume(throwing: err)
                } else if let token = token {
                    cont.resume(returning: token)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "Auth",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Missing ID token"]
                    ))
                }
            }
        }


        // 🔁 Cloud Run base URL
        let baseURL = "https://translate-api-1047255165048.europe-west1.run.app"
        guard let url = URL(string: "\(baseURL)/delete_model_from_published") else {
            throw NSError(
                domain: "URL",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Bad delete URL"]
            )
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let body = DeletePublishedRequest(
            modelName: modelName,
            storageRoot: storageRoot
        )

        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse

        if http?.statusCode ?? 500 >= 400 {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "DeletePublishedAPI",
                code: http?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Delete API failed (\(http?.statusCode ?? 0)): \(text)"]
            )
        }

        let decoded = try? JSONDecoder().decode(DeletePublishedResponse.self, from: data)
        if decoded?.success != true {
            throw NSError(
                domain: "DeletePublishedAPI",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey:
                    decoded?.error ?? "Delete failed"]
            )
        }
    }

    func deleteModelFromPublished(
        modelName: String,
        storageRoot: String = "PublishedModels",
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task {
            do {
                // 1) Delete from Published (Cloud Run)
                try await self.callDeleteModelFromPublishedAPI(
                    modelName: modelName,
                    storageRoot: storageRoot
                )

                // 2) After successful deletion, delete the "new model" (your second API)
                self.callDeleteNewModel(modelName: modelName) { result in
                    switch result {
                    case .success:
                        DispatchQueue.main.async {
                            completion(.success(()))
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    }
                }

            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }


    /// Recursively deletes a folder in Firebase Storage.
    private func deleteFolderRecursively(
        ref: StorageReference,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        ref.listAll { result, err in
            if let err = err { return completion(.failure(err)) }

            let items = result?.items ?? []
            let prefixes = result?.prefixes ?? []

            // Delete all files first
            let group = DispatchGroup()
            var firstError: Error?

            for item in items {
                group.enter()
                item.delete { delErr in
                    if let delErr = delErr, firstError == nil { firstError = delErr }
                    group.leave()
                }
            }

            // Then recurse into subfolders
            for folder in prefixes {
                group.enter()
                self.deleteFolderRecursively(ref: folder) { res in
                    if case .failure(let e) = res, firstError == nil { firstError = e }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                // Finally, try to delete the parent folder "marker" (not strictly required; Storage is virtual)
                ref.delete { _ in
                    if let e = firstError { completion(.failure(e)) }
                    else { completion(.success(())) }
                }
            }
        }
    }

}
