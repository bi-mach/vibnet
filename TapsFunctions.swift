





import SwiftUI
import Foundation
import Firebase
import FirebaseStorage
import CoreBluetooth
import FirebaseFirestore
import FirebaseAuth
class TapsFunctions: ObservableObject {
    
    @EnvironmentObject var personalModelsFunctions: PersonalModelsFunctions
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    
    func SaveTAPS(
        for userEmail: String?,
        selectedModel: String,
        SaveToFolder: String,
        UsersTaps: [Int: String],
        completion: @escaping (Bool) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(false)
            return
        }


        let effectiveIdentifier: String
        if let email = userEmail, !email.isEmpty {
            
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            
            effectiveIdentifier = user.uid
        }

        
        let storageRef = Storage.storage().reference()
        let modelRootRef = storageRef
            .child("Users/\(effectiveIdentifier)/Models/\(selectedModel)/")
        
        
        if !SaveToFolder.isEmpty {
            let folderRef = modelRootRef.child(SaveToFolder)
            self.uploadTaps(
                to: folderRef,
                userEmail: effectiveIdentifier,
                selectedModel: selectedModel,
                usersTaps: UsersTaps,
                completion: completion
            )
            return
        }
        
        
        modelRootRef.listAll { result, error in
            if let error = error {
                
                completion(false)
                return
            }
            
            let existingNames = Set(result?.prefixes.map { $0.name } ?? [])
            var folderName: String = ""
            var idx = 0
            while true {
                let candidate = "Memory\(idx)"
                if !existingNames.contains(candidate) {
                    folderName = candidate
                    break
                }
                idx += 1
            }
            
            let folderRef = modelRootRef.child(folderName)
            self.uploadTaps(
                to: folderRef,
                userEmail: effectiveIdentifier,
                selectedModel: selectedModel,
                usersTaps: UsersTaps,
                completion: completion
            )
        }
    }
    
    
    func SaveTAPSForFav(
        for userEmail: String?,
        selectedModel: String,
        SaveToFolder: String,
        UsersTaps: [Int: String],
        completion: @escaping (Bool) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(false)
            return
        }

        let effectiveIdentifier: String
        if let email = userEmail, !email.isEmpty {
            
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            
            effectiveIdentifier = user.uid
        }


        let storageRef   = Storage.storage().reference()
        let modelRootRef = storageRef.child("Users/\(effectiveIdentifier)/FavouriteModels/\(selectedModel)/")

        
        modelRootRef.listAll { result, error in
            if let error = error {
                
                completion(false)
                return
            }

            let hasAnything =
                ((result?.items.isEmpty == false) || (result?.prefixes.isEmpty == false))

            guard hasAnything else {
                
                completion(false)
                return
            }

            
            if !SaveToFolder.isEmpty {
                let folderRef = modelRootRef.child(SaveToFolder)
                self.uploadTapsForFav(
                    to: folderRef,
                    userEmail: effectiveIdentifier,
                    selectedModel: selectedModel,
                    usersTaps: UsersTaps,
                    completion: completion
                )
                return
            }

            
            let existingNames = Set(result?.prefixes.map { $0.name } ?? [])
            var folderName = ""
            var idx = 0
            while true {
                let candidate = "Memory\(idx)"
                if !existingNames.contains(candidate) {
                    folderName = candidate
                    break
                }
                idx += 1
            }

            let folderRef = modelRootRef.child(folderName)
            self.uploadTapsForFav(
                to: folderRef,
                userEmail: effectiveIdentifier,
                selectedModel: selectedModel,
                usersTaps: UsersTaps,
                completion: completion
            )
        }
    }

    
    
    func fetchConfigForMyModel(
        userEmail: String,
        ModelName: String,
        completion: @escaping (Result<(taps: [Int: [Int: [TapEntry]]], names: [Int: [Int: String]]), Error>) -> Void
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
        if !userEmail.isEmpty {
            effectiveIdentifier = userEmail
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            effectiveIdentifier = user.uid
        }
        
        let storage = Storage.storage()
        let folder = storage.reference().child("Users/\(effectiveIdentifier)/Models/\(ModelName)")

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
    
    func saveCommandNamesForMyModel(
        userEmail: String,
        ModelName: String,
        commandNames: [Int: [Int: String]],
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
        if !userEmail.isEmpty {
            effectiveIdentifier = userEmail
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            effectiveIdentifier = user.uid
        }
        
        let storage = Storage.storage()
        let namesRef = storage
            .reference()
            .child("Users/\(effectiveIdentifier)/Models/\(ModelName)/ModelNames.json")

        func mapKeysToString(_ dict: [Int: [Int: String]]) -> [String: [String: String]] {
            var out: [String: [String: String]] = [:]
            for (k, inner) in dict {
                var innerOut: [String: String] = [:]
                for (ik, v) in inner {
                    innerOut[String(ik)] = v
                }
                out[String(k)] = innerOut
            }
            return out
        }

        do {
            let payload = mapKeysToString(commandNames)
            let data = try JSONEncoder().encode(payload)
            let metadata = StorageMetadata()
            metadata.contentType = "application/json"

            namesRef.putData(data, metadata: metadata) { _, error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        } catch {
            completion(.failure(error))
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
    
    private func uploadTaps(
        to folderRef: StorageReference,
        userEmail: String,
        selectedModel: String,
        usersTaps: [Int: String],
        completion: @escaping (Bool) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(false)
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

        
        fetchConfigForMyModel(userEmail: effectiveIdentifier, ModelName: selectedModel) { result in
            switch result {
            case .failure(let error):
                
                completion(false)

            case .success(let payload):
                let TAPSConfig    = payload.taps
                let commandNames  = payload.names

                
                do {
                    
                    let usersTapsData = try JSONEncoder().encode(usersTaps)
                    let tapsConfigData = try JSONEncoder().encode(TAPSConfig)

                    
                    let modelNamesData = try JSONEncoder().encode(commandNames)

                    
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    let descData = fmt.string(from: Date()).data(using: .utf8)!

                    
                    let usersTapsRef   = folderRef.child("usersTaps.json")
                    let tapsConfigRef  = folderRef.child("tapsConfig.json")
                    let modelNamesRef  = folderRef.child("ModelNames.json")
                    let descRef        = folderRef.child("description.txt")

                    
                    let group = DispatchGroup()
                    var success = true

                    
                    group.enter()
                    usersTapsRef.putData(usersTapsData, metadata: nil) { _, err in
                        if let err = err {
                            
                            success = false
                        }
                        group.leave()
                    }

                    
                    group.enter()
                    tapsConfigRef.putData(tapsConfigData, metadata: nil) { _, err in
                        if let err = err {
                            
                            success = false
                        }
                        group.leave()
                    }

                    
                    group.enter()
                    modelNamesRef.putData(modelNamesData, metadata: nil) { _, err in
                        if let err = err {
                            
                            success = false
                        }
                        group.leave()
                    }

                    
                    group.enter()
                    descRef.putData(descData, metadata: nil) { _, err in
                        if let err = err {
                            
                            success = false
                        }
                        group.leave()
                    }

                    
                    group.notify(queue: .main) {
                        completion(success)
                    }

                } catch {
                    
                    completion(false)
                }
            }
        }
    }

    private func uploadTapsForFav(
        to folderRef: StorageReference,
        userEmail: String,
        selectedModel: String,
        usersTaps: [Int: String],
        completion: @escaping (Bool) -> Void
    ) {
        fetchConfigForPublishedModel(modelName: selectedModel) { result in
            switch result {
            case .failure(let error):
                
                completion(false)

            case .success(let payload):
                let TAPSConfig    = payload.taps
                let commandNames  = payload.names

                
                do {
                    
                    let usersTapsData = try JSONEncoder().encode(usersTaps)
                    let tapsConfigData = try JSONEncoder().encode(TAPSConfig)

                    
                    let modelNamesData = try JSONEncoder().encode(commandNames)

                    
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    let descData = fmt.string(from: Date()).data(using: .utf8)!

                    
                    let usersTapsRef   = folderRef.child("usersTaps.json")
                    let tapsConfigRef  = folderRef.child("tapsConfig.json")
                    let modelNamesRef  = folderRef.child("ModelNames.json")
                    let descRef        = folderRef.child("description.txt")

                    
                    let group = DispatchGroup()
                    var success = true

                    
                    group.enter()
                    usersTapsRef.putData(usersTapsData, metadata: nil) { _, err in
                        if let err = err {
                            
                            success = false
                        }
                        group.leave()
                    }

                    
                    group.enter()
                    tapsConfigRef.putData(tapsConfigData, metadata: nil) { _, err in
                        if let err = err {
                            
                            success = false
                        }
                        group.leave()
                    }

                    
                    group.enter()
                    modelNamesRef.putData(modelNamesData, metadata: nil) { _, err in
                        if let err = err {
                            
                            success = false
                        }
                        group.leave()
                    }

                    
                    group.enter()
                    descRef.putData(descData, metadata: nil) { _, err in
                        if let err = err {
                            
                            success = false
                        }
                        group.leave()
                    }

                    
                    group.notify(queue: .main) {
                        completion(success)
                    }

                } catch {
                    
                    completion(false)
                }
            }
        }
    }

    func extractUsersTapsAndConfig(
        userEmail: String,
        modelName: String,
        memory: String,
        isFav: Bool,
        completion: @escaping (_ usersTaps: [Int:String], _ tapsConfig: TAPSConfig?) -> Void
    ) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion([:], nil)
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


        let folder = isFav ? "FavouriteModels" : "Models"
        let baseRef = Storage.storage().reference()
            .child("Users/\(effectiveIdentifier)/\(folder)/\(modelName)/\(memory)")
        let usersTapsRef = baseRef.child("usersTaps.json")
        let tapsConfigRef = baseRef.child("tapsConfig.json")

        let group = DispatchGroup()
        var usersTaps: [Int:String] = [:]
        var tapsConfig: TAPSConfig?
 
        group.enter()
        usersTapsRef.getData(maxSize: 5 * 1024 * 1024) { data, error in
            defer { group.leave() }
            guard error == nil, let data = data else {
                
                return
            }
            do {
                
                usersTaps = try JSONDecoder().decode([Int:String].self, from: data)
                
            } catch {
                
                do {
                    let legacy = try JSONDecoder()
                        .decode([Int: [String: [String: [Double]]]].self, from: data)
                    var rebuilt: [Int:String] = [:]
                    for (idx, dict) in legacy {
                        if let firstKey = dict.keys.first { rebuilt[idx] = firstKey }
                    }
                    usersTaps = rebuilt
                    
                } catch {
                    
                }
            }
        }

        
        group.enter()
        tapsConfigRef.getData(maxSize: 5 * 1024 * 1024) { data, error in
            defer { group.leave() }
            guard error == nil, let data = data else {
                
                return
            }
            do {
                let decoded = try JSONDecoder().decode(TAPSConfig.self, from: data)
                tapsConfig = decoded
                
            } catch {
                
            }
        }

        group.notify(queue: .main) {
            completion(usersTaps, tapsConfig)
        }
    }
     
    func fetchFolderNames(
        for userEmail: String,
        selectedModel: String,
        completion: @escaping (Result<[Int: String], Error>) -> Void
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
        if !userEmail.isEmpty {
            effectiveIdentifier = userEmail
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            effectiveIdentifier = user.uid
        }

        let storageRef = Storage.storage()
            .reference()
            .child("Users/\(effectiveIdentifier)/Models/\(selectedModel)/")

        storageRef.listAll { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let folderNames = result?.prefixes.map { $0.name } ?? []

            var memoryMap: [Int: String] = [:]

            for name in folderNames {
                guard name.hasPrefix("Memory") else { continue }
                let suffix = name.dropFirst("Memory".count)
                if let index = Int(suffix), memoryMap[index] == nil {
                    memoryMap[index] = name
                }
            }

            completion(.success(memoryMap))
        }
    }

    func fetchFolderNamesForFav(
        for userEmail: String,
        selectedModel: String,
        completion: @escaping (Result<[Int: String], Error>) -> Void
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
        if !userEmail.isEmpty {
            effectiveIdentifier = userEmail
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            effectiveIdentifier = user.uid
        }
        let storageRef = Storage.storage()
            .reference()
            .child("Users/\(effectiveIdentifier)/FavouriteModels/\(selectedModel)/")

        storageRef.listAll { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let folderNames = result?.prefixes.map { $0.name } ?? []

            var memoryMap: [Int: String] = [:]

            for name in folderNames {
                guard name.hasPrefix("Memory") else { continue }
                let suffix = name.dropFirst("Memory".count)
                if let index = Int(suffix), memoryMap[index] == nil {
                    memoryMap[index] = name
                }
            }

            completion(.success(memoryMap))
        }
    }
    
    func getImageFromFirebase(userEmail: String?, completion: @escaping (UIImage?) -> Void) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion(nil)
            return
        }


        
        let effectiveIdentifier: String
        if let email = userEmail, !email.isEmpty {
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let email = user.email, !email.isEmpty {
            
            effectiveIdentifier = email
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            
            effectiveIdentifier = user.uid
        }
        
        let storageRef = Storage.storage().reference().child("Users/\(effectiveIdentifier)/ProfileImage.png")
        
        
        
        storageRef.getData(maxSize: 5 * 1024 * 1024) { data, error in
            if let error = error {
                
                completion(nil)
                return
            }
            
            guard let data = data else {
                
                completion(nil)
                return
            }
            
            guard let image = UIImage(data: data) else {
                
                completion(nil)
                return
            }
            
            
            completion(image)
        }
    }
    
    
}
