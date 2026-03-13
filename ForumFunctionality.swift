//
//  ForumFunctionality.swift
//  Vibro
//
//  Created by lyubcsenko on 02/09/2025.
//

import SwiftUI
import Foundation
import Firebase
import FirebaseDatabase
import FirebaseAuth
import FirebaseFirestore

extension ForumFunctionality {
    func observeForumPosts(
        forumTag: String,
        onChange: @escaping (Result<[ForumPost], Error>) -> Void
    ) -> DatabaseHandle {
        let ref = FirebaseRefs.db.reference().child("forumPosts")
        let query = ref
            .queryOrdered(byChild: "forumTag")
            .queryEqual(toValue: forumTag)

        
        let handle = query.observe(.value) { snapshot in
            var results: [ForumPost] = []

            for child in snapshot.children.allObjects as? [DataSnapshot] ?? [] {
                guard
                    let dict = child.value as? [String: Any],
                    let tag = dict["forumTag"] as? String,
                    let text = dict["text"] as? String,
                    let userId = dict["userId"] as? String,
                    let messageType = dict["messageType"] as? String
                else { continue }

                let ms = (dict["createdAt"] as? TimeInterval) ?? 0
                let createdAtSec = ms > 1_000_000_000_000 ? ms / 1000.0 : ms

                results.append(ForumPost(
                    id: child.key,
                    forumTag: tag,
                    messageType: messageType,
                    text: text,
                    userId: userId,
                    createdAt: createdAtSec
                ))
            }

            results.sort { $0.createdAt > $1.createdAt }
            DispatchQueue.main.async { onChange(.success(results)) }
        }

        
        return handle
    }

    func stopObserving(handle: DatabaseHandle, forumTag: String) {
        let ref = FirebaseRefs.db.reference().child("forumPosts")
        let query = ref
            .queryOrdered(byChild: "forumTag")
            .queryEqual(toValue: forumTag)
        query.removeObserver(withHandle: handle)
    }
}


private func base64URLEncode(_ string: String) -> String {
    let data = Data(string.utf8)
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

final class ForumFunctionality: ObservableObject {
    func sendForumPost(
        forumTag: String,
        text: String,
        messageType: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
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

        let uid = user.uid

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return completion(.failure(NSError(
                domain: "Validation",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Text cannot be empty"]
            )))
        }
        
        let post: [String: Any] = [
            "forumTag": forumTag,
            "text": trimmedText,
            "messageType" : messageType,
            "userId": uid,
            "createdAt": ServerValue.timestamp()
        ]
        
        let ref = FirebaseRefs.db.reference().child("forumPosts").childByAutoId()
        
        ref.setValue(post) { error, _ in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(ref.key ?? ""))
                }
            }
        }
    }
    
    
    func sendUserReport(
        forumTag: String,
        reason: String,
        reportedUserUID: String,
        completion: @escaping (Result<String, Error>) -> Void
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

        let reporterUID = user.uid


        // 2) Validate inputs
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            return completion(.failure(NSError(
                domain: "Validation", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Reason cannot be empty"]
            )))
        }
        guard !reportedUserUID.isEmpty else {
            return completion(.failure(NSError(
                domain: "Validation", code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Reported user UID is required"]
            )))
        }
        guard reportedUserUID != reporterUID else {
            return completion(.failure(NSError(
                domain: "Validation", code: -4,
                userInfo: [NSLocalizedDescriptionKey: "You cannot report yourself"]
            )))
        }

        // 3) Build ref & ID under top-level "Reports"
        let ref = FirebaseRefs.db.reference().child("Reports").childByAutoId()
        guard let reportID = ref.key else {
            return completion(.failure(NSError(
                domain: "Firebase", code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Could not generate report ID"]
            )))
        }

        // 4) Payload (UID-only, minimal)
        let report: [String: Any] = [
            "id": reportID,
            "type": "user_report",
            "forumTag": forumTag,
            "reason": trimmedReason,
            "reportedUserId": reportedUserUID,
            "reporterUserId": reporterUID,
            "status": "pending",
            "createdAt": ServerValue.timestamp()
        ]

        // 5) Single write (ModelUsage style)
        ref.setValue(report) { error, _ in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)) }
                else { completion(.success(reportID)) }
            }
        }
    }

    
    func fetchMessageCountInLastMinute(forumTag: String, completion: @escaping (Int) -> Void) {
        let ref = FirebaseRefs.db.reference().child("forumPosts")
        let sinceMs = Date().addingTimeInterval(-60).timeIntervalSince1970 * 1000
        let needle = forumTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        ref
            .queryOrdered(byChild: "createdAt")
            .queryStarting(atValue: sinceMs)
            .observeSingleEvent(of: .value) { snapshot in
                guard let allPosts = snapshot.value as? [String: [String: Any]] else {
                    completion(0)
                    return
                }

                func matchesTag(_ dict: [String: Any]) -> Bool {
                    
                    if let tagStr = dict["forumTag"] as? String {
                        let tags = tagStr
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                            .filter { !$0.isEmpty }
                        if tags.contains(needle) { return true }
                        
                        if tags.isEmpty && tagStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle {
                            return true
                        }
                    }
                    
                    if let tagsArr = dict["forumTags"] as? [String] {
                        let tags = tagsArr
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                            .filter { !$0.isEmpty }
                        if tags.contains(needle) { return true }
                    }
                    return false
                }

                var uniqueUsers = Set<String>()

                for post in allPosts.values {
                    
                    let createdMs: Double? = {
                        if let n = post["createdAt"] as? NSNumber { return n.doubleValue }
                        if let d = post["createdAt"] as? Double   { return d }
                        if let i = post["createdAt"] as? Int      { return Double(i) }
                        return nil
                    }()

                    guard let createdMs, createdMs >= sinceMs else { continue }
                    guard matchesTag(post) else { continue }
                    guard let uid = post["userId"] as? String, !uid.isEmpty else { continue }

                    uniqueUsers.insert(uid)
                }

                completion(uniqueUsers.count)
            }
    }
}
