# Re-Design Goals
These goals are relative to the prior [client](https://github.com/crspybits/SyncServer-iOSClient/).

## Build the client so as to make it generally possible to later port to Android. 
E.g., use SqLite, and don't depend in the basic library on iOS UI features such as UIKit. This will also mean splitting off the sign-in components to their own library.
	
## Design data architecture so extensions can be used. Shared container?
Can a library enforce this?
			
## Re-think the main file structure: Can it be made simpler?
https://github.com/crspybits/SyncServer-Shared/blob/dev/Sources/SyncServerShared/RequestsAndResponses/FileInfo.swift
Also look at the collection of versions. I think there is more than just a file version.
	
## Make it easier to add in new file types.
E.g., a video file type.
	
## Enable migration from prior Core Data structures.
	
## I want the client to have more control over file downloading. That is, currently the library takes control over when and how how many files are downloaded from the server. Instead, I want the client app to take charge of this triggering-- e.g., so the client can decide what to do in the foreground and what to do in the background. I think the same situation applies for uploads. E.g., if there are 10 files needing upload, the client will trigger the "when" of those uploads.
In terms of downloading-- the client should also have control over what types of files get downloaded first. E.g., if there are icon images, the client should be able to prioritize those.
Also, the client should be able to have attribute information on other files for figuring out how to prioritize their download.
	
## Generally, I want it to be easier for an app to be written to use this library. Right now, it's pretty complicated.
One of these issues are dealing with different ordering of file downloads. Sharing groups can have multiple files. And those files can be downloaded in different orders. And this means an application has to deal with integrating those files into its own data in various ways depending on those download orderings. Could we unify the download of sharing groups with different sets of files? OR-- Perhaps that'll be dealt with by providing the application with control over downloading-- which we are planning to do!!
	
## I want the conflict resolution mechanism to be simpler in terms of the app's coding. Even if we have to take some strong opinions about conflict resolution.
	
## Need to reconsider UUID collisions. 
	
## Overall "master version" model-- this is constraining. And could use a more general model.
	
## Permission model. Rethink.
I'd like to have this more general. E.g., to be able to make one file completely public.
