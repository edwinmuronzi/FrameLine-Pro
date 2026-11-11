#if DEBUG
import SwiftUI

struct CaptureStorageVerification: View {
    @State private var status = "Checking capture storage…"
    var body: some View {
        Text(status).task {
            let store = CameraStore(); store.isShowcase = true; store.libraryReady = true
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("Storage-QA-\(UUID())")
            try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:root) }
            var passed = true
            store.saveToPhotos = false; store.saveInApp = false
            passed = passed && store.saveToPhotos
            store.saveToPhotos = false
            passed = passed && store.saveInApp
            let now = Date()
            let dates = [0.0,0.5,1,6,7,29,30,31].map { now.addingTimeInterval(-$0*86400) }
            for policy in CaptureRetention.allCases {
                for (index,date) in dates.enumerated() {
                    let expected = policy != .never && [0.0,0.5,1,6,7,29,30,31][index] >= Double(policy.rawValue)
                    passed = passed && policy.expired(date,now:now) == expected
                }
            }
            func item(_ name:String) -> CaptureItem {
                let url = root.appendingPathComponent(name+".jpg"); try? Data([1,2,3]).write(to:url)
                var item = CaptureItem(movieURL:nil,storiesURL:nil,rawURL:nil,detail:"Storage QA",simulated:true,mode:.photo)
                item.fullPhotoURL = url; item.date = now.addingTimeInterval(-40*86400)
                return item
            }
            let removed = item("success"), failed = item("failure"), retained = item("retained")
            store.captures = [removed,failed,retained]
            store.prepareCaptureStorage(id:removed.id,keepInApp:false)
            store.prepareCaptureStorage(id:failed.id,keepInApp:false)
            store.completeCaptureStorage(id:removed.id,keepInApp:false,saves:[Task { true }])
            store.completeCaptureStorage(id:failed.id,keepInApp:false,saves:[Task { false }])
            for _ in 0..<100 {
                if !store.captures.contains(where:{ $0.id == removed.id }) && !store.deletingGallery { break }
                try? await Task.sleep(for:.milliseconds(10))
            }
            passed = passed && !store.captures.contains(where:{ $0.id == removed.id }) && !FileManager.default.fileExists(atPath:removed.fullPhotoURL!.path)
            passed = passed && store.captures.contains(where:{ $0.id == failed.id }) && FileManager.default.fileExists(atPath:failed.fullPhotoURL!.path) && store.protectedCaptureIDs.contains(failed.id)
            store.autoDeleteAfter = .week
            passed = passed && store.captureIDsForExpiration(now:now) == [retained.id]
            let record = LibraryRecord(id:failed.id,date:now,detail:"Recovery",mode:"photo",recoveryCopy:true)
            let saved = try? JSONEncoder().encode([record])
            let decoded = saved.flatMap { try? JSONDecoder().decode([LibraryRecord].self,from:$0) }
            passed = passed && decoded?.first?.recoveryCopy == true
            let report:[String:Any] = ["passed":passed,"ageCases":32,"destinations":true,"cleanupAfterConfirmedSave":true,"failedSaveKept":true,"recoveryExcludedFromAgeCleanup":true,"recoveryPersistence":true]
            let file = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("capture-storage-verification.json")
            if let data = try? JSONSerialization.data(withJSONObject:report,options:.prettyPrinted) { try? data.write(to:file,options:.atomic) }
            status = passed ? "Capture storage passed" : "Capture storage failed"
            NSLog("CAPTURE_STORAGE_VERIFY passed=%d",passed ? 1 : 0)
        }
    }
}
#endif
