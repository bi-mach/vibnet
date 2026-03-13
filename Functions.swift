





import SwiftUI
import Foundation
import Firebase
import FirebaseStorage
import CoreBluetooth
import FirebaseFirestore
import FirebaseAuth

class Functions: ObservableObject {
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    
    func nameVariants100() -> [String] {
        let firstNames = [
            "Alex","Jamie","Taylor","Morgan","Jordan","Casey","Riley","Avery","Skyler","Quinn",
            "Charlie","Drew","Peyton","Rowan","Emerson","Cameron","Elliot","Hayden","Sage","Arden"
        ] 

        let lastNames = [
            "Smith","Johnson","Brown","Taylor","Anderson","Thomas","Moore","Jackson","White","Harris",
            "Clark","Lewis","Walker","Young","Allen","King","Wright","Scott","Green","Baker"
        ] 

        
        var names: [String] = []
        var i = 0
        var j = 0
        while names.count < 100 {
            names.append("\(firstNames[i]) \(lastNames[j])")
            i = (i + 3) % firstNames.count   
            j = (j + 7) % lastNames.count
            
            if names.count > 1 && names.last == names[names.count - 2] {
                j = (j + 1) % lastNames.count
            }
        }
        return names
    }

    func pickUserName(for email: String) -> String {
        let variants = nameVariants100()
        let idx = abs(email.hashValue) % variants.count
        return variants[idx]
    }

    func pickRandomUserName() -> String {
        let variants = nameVariants100()
        return variants.randomElement() ?? "Alex Smith"
    }

    private func fetchUniqueUserName(db: Firestore,
                                     maxAttempts: Int = 50,
                                     generate: @escaping () -> String,
                                     completion: @escaping (String?) -> Void) {
        func attempt(_ n: Int) {
            guard n < maxAttempts else { completion(nil); return }

            let candidate = generate()
            db.collection("Followers")
                .whereField("UserName", isEqualTo: candidate)
                .limit(to: 1)
                .getDocuments { snap, err in
                    if let err = err {
                        
                        completion(nil)
                        return
                    }
                    if let snap = snap, snap.isEmpty {
                        completion(candidate)        
                    } else {
                        attempt(n + 1)               
                    }
                }
        }
        attempt(0)
    }

    func createUserFolder(user: String, userName: String, completion: @escaping (Bool) -> Void) {
        let storage = Storage.storage()
        let db = Firestore.firestore()

        guard let currentUser = Auth.auth().currentUser, !currentUser.isAnonymous else {
            completion(false)
            return
        }

        let uid = currentUser.uid

        // Keep your identifier logic (prefer email, else uid)
        let effectiveIdentifier: String
        if let email = currentUser.email, !email.isEmpty {
            effectiveIdentifier = email
        } else {
            effectiveIdentifier = uid
        }

        let rootRef = storage.reference()
        let userFolderRef = rootRef.child("Users").child(effectiveIdentifier)

        userFolderRef.listAll { result, error in
            if let error = error {
                print("[ERROR] listAll: \(error.localizedDescription)")
                completion(false)
                return
            }

            // If folder already has prefixes, treat as "exists"
            if let result = result, !result.prefixes.isEmpty {
                completion(true)
                return
            }

            // Decide final username:
            // 1) use passed-in real name if non-empty
            // 2) else generate a unique random one
            let trimmedIncomingName = userName.trimmingCharacters(in: .whitespacesAndNewlines)

            func proceedToCreate(using finalName: String) {
                createAll(for: finalName)
            }

            if !trimmedIncomingName.isEmpty {
                // Ensure uniqueness using your existing helper
                self.fetchUniqueUserName(db: db, generate: { trimmedIncomingName }) { uniqueName in
                    guard let uniqueName = uniqueName else {
                        completion(false)
                        return
                    }
                    proceedToCreate(using: uniqueName)
                }
            } else {
                self.fetchUniqueUserName(db: db, generate: { self.pickRandomUserName() }) { uniqueName in
                    guard let uniqueName = uniqueName else {
                        completion(false)
                        return
                    }
                    proceedToCreate(using: uniqueName)
                }
            }

            func createAll(for uniqueName: String) {
                let modelsRef = userFolderRef.child("Models")
                let placeholderData = "This folder was created for user \(effectiveIdentifier)".data(using: .utf8)!

                modelsRef.child("placeholder.txt").putData(placeholderData, metadata: nil) { _, error in
                    if let error = error {
                        print("[ERROR] create Models placeholder: \(error.localizedDescription)")
                        completion(false)
                        return
                    }

                    // Create ProfileImages folder placeholder
                    let profileImagesRef = rootRef.child("ProfileImages").child(uid)
                    profileImagesRef.child("placeholder.txt")
                        .putData("Profile image folder created".data(using: .utf8)!, metadata: nil) { _, err in
                            if let err = err {
                                print("[WARN] ProfileImages placeholder: \(err.localizedDescription)")
                            }
                        }

                    // Create FavouriteModels folder placeholder
                    let favouriteModelsRef = userFolderRef.child("FavouriteModels")
                    favouriteModelsRef.child("placeholder.txt")
                        .putData("FavouriteModels folder created".data(using: .utf8)!, metadata: nil) { _, err in
                            if let err = err {
                                print("[WARN] FavouriteModels placeholder: \(err.localizedDescription)")
                            }
                        }

                    let followersData: [String: Any] = ["UserName": uniqueName]
                    let userData: [String: Any] = [
                        "Models": [:],
                        "UserName": uniqueName,
                        "userEmail": effectiveIdentifier
                    ]

                    db.collection("Users").document(uid).setData(userData) { firestoreError in
                        if let firestoreError = firestoreError {
                            print("[ERROR] Firestore Users setData: \(firestoreError.localizedDescription)")
                            completion(false)
                            return
                        }

                        db.collection("Followers").document(uid).setData(followersData) { error in
                            if let error = error {
                                print("[ERROR] Firestore Followers setData: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                completion(true)
                            }
                        }
                    }
                }
            }
        }
    }

    func doesUserExist(user: String, completion: @escaping (Bool) -> Void) {
        guard
            let currentUser = Auth.auth().currentUser,
            !currentUser.isAnonymous
        else {
            
            completion(false)
            return
        }

        let effectiveIdentifier = currentUser.uid

        let db = Firestore.firestore()
        db.collection("Users").getDocuments { snapshot, error in
            if let error = error {
                
                completion(false)
                return
            }

            
            if let documents = snapshot?.documents {
                for document in documents {
                    if document.documentID == effectiveIdentifier {
                        completion(true)
                        return
                    }
                }
            }

            completion(false)
        }
    }

    func loadTheMap(completion: @escaping (Result<[String: [Double]], Error>) -> Void) {
        let fileRef = storage.reference(withPath: "data.json")
        let oneMegabyte: Int64 = 1024 * 1024
        
        fileRef.getData(maxSize: oneMegabyte) { data, error in
            if let error = error {
                
                completion(.failure(error))
                return
            }
            
            guard let data = data, !data.isEmpty else {
                let noDataError = NSError(
                    domain: "",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "No data found for data.json"]
                )
                
                completion(.failure(noDataError))
                return
            }
            
            do {
                
                if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: [Any]] {
                    var dataMap: [String: [Double]] = [:]
                    
                    for (key, array) in jsonObject {
                        let doubleList = array.compactMap { element -> Double? in
                            if let number = element as? NSNumber {
                                return number.doubleValue
                            }
                            if let str = element as? String, let doubleVal = Double(str) {
                                return doubleVal
                            }
                            return nil
                        }
                        dataMap[key] = doubleList
                    }
                    completion(.success(dataMap))
                } else {
                    let parseError = NSError(
                        domain: "",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON structure"]
                    )
                    
                    completion(.failure(parseError))
                }
            } catch {
                
                completion(.failure(error))
            }
        }
    }
    
}
