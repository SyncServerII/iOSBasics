
import Foundation

extension SyncServer {
    // Figure out which uploads are in an error state and need to be restarted.
    func reTriggerUploads() {
        /*
        case notStarted
        case uploading
        
        // This is for both successfully uploaded files and files that cannot be uploaded due to a gone response. For vN files this just means the first stage of the upload has completed. The full deferred upload hasn't necessarily completed yet.
        case uploaded
        */
        
        /*
        Possibilities for upload State.
            all notStarted
                Current TriggerUploads will handle
                
            all uploading
                Expected  normal state. No action needed.
                
            all uploaded
                Should be transient.
                
            some notStarted, some uploading
                Error state. Current TriggerUploads will not handle.
                
            some notStarted, some uploaded
                Error state. Current TriggerUploads will not handle.
                
            some uploading, some uploaded
                Expected  normal state. No action needed.
                
            some notStarted, some uploading, some uploaded
                Error state.
                
        Possible algorithm:
            1) Get the fileGroupUUID for any object with a uploading state file.
            2) We can re-trigger the upload for any upload in an error state where it's object is not one of those objects currently uploading.
            3) It seems like this is the time we want to consider the time of times an upload has been tried/retried. We should ony try a specific number of times before giving up.
            
        How to test? We need some way to reset the state of an upload to .notStarted. Might be able to do that in a test just after learning its upload was successful.
        What happens if the same upload is carried out more than once?
        Cases:
            1 out of 1 upload for v0, no change resolver
                Server never received upload (due to error):
                    Re-attempted upload works.
                    
                [FAIL] Server received upload: (*)
                    This will be received as a second upload for the same file. It will fail.
                    How to handle? Server could possibly report some error code analogous to "gone"-- "duplicate".
            
            1 out of 1 upload for v0, with change resolver
                Server never received upload (due to error):
                    Re-attempted upload works.
                    
                [FAIL] Server received upload:
                    The v0 upload will contain v0 only data, such as change resolver, mime type etc. It will fail. This case is really the same as (*).

            1 out of 1 upload for vN
                Server never received upload (due to error):
                    Re-attempted upload works.
                    
                Server received upload:
                    This is handled normally, and applied as a change to the file.
                    Since we require re-applying of the same change to be handled without error, this is OK.

            N out of M uploads for v0-- only one file is .notStarted on client; the rest were successfully uploaded.
            
                Server never received upload (due to error):
                    Re-attempted upload works.
                    
                Server received upload:
                    The uploads would have been processed and (possibly) flushed from the Upload table.
                    NEEDS TESTING: What happens if the deferred uploading hasn't finished yet and the re-upload arrives before the Uploads flushed?
                    If the uploads have been flushed, then this is a case where the upload would just linger. We would never get the deferred upload id in response to a "last upload.
                    Possibilities:
                        1) Server responds with deferred id after each upload in batch.
                            That id could be used to query.
                        2) Client queries state of uploads.
                    
         */
    }
}
