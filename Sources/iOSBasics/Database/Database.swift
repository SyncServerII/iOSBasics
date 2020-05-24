/* Data model:
    The first two queues are needed because network operatons can fail, and the app can terminate. And we will need to restart operations.
    
    a) Queue of pending uploads
        - Each upload has a status: InProgress, NotStarted
        - In general there is a queue of queue structure. E.g., a client could queue up a set of files, and then queue up another set of files.  The first upload won't be attempted if there are files needing to be downloaded-- and the download triggering will be driven by the client.
    b) Queue of pending downloads.
    c) List of meta data for files
        - These are files that have been downloaded and handed off to client.
    d) Network cache: When a download or upload completes, the first action is to persist a network cache object describing that upload or download. This is because a upload or download may complete in the background and we need to have a record of the download or upload.
        - I'm not 100% sure this object is needed. How is a match done later between a Network cache object and the pending upload or download objects? What function is this object really serving?
*/
class Database {

}
