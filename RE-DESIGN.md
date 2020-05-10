# General Re-Design Goals
These goals are relative to the prior [client](https://github.com/crspybits/SyncServer-iOSClient/).

## Build the client so as to make it generally possible to later port to Android. 
E.g., use SqLite, and don't depend in the basic library on iOS UI features such as UIKit. This will also mean splitting off the sign-in components to their own library.
Windows may be a target too-- Swift is about to be available there.
Web UI is also a possiblity, but that seems out of the Swift realm.
	
## Design data architecture so extensions can be used. 
This is so that I can have a Sharing Extension, where in the Apple Photos app, you can get an app like Neebla to upload a file. Currently the architecture of the iOS client and Neebla won't allow for this.
Use a shared container? Can a library enforce this?
			
## Re-think the main file structure: Can it be made simpler?
https://github.com/crspybits/SyncServer-Shared/blob/dev/Sources/SyncServerShared/RequestsAndResponses/FileInfo.swift
Also look at the collection of versions. I think there is more than just a file version.
	
## Make it easier to add in new file types.
E.g., a video file type, and a HEIC file type.
And [live photos](https://stackoverflow.com/questions/32508375/apple-live-photo-file-format).
	
## Enable migration from prior Core Data structures.
	
## I want the client to have more control over file downloading. 
That is, currently the library takes control over when and how how many files are downloaded from the server. Instead, I want the client app to take charge of this triggering-- e.g., so the client can decide what to do in the foreground and what to do in the background. I think the same situation applies for uploads. E.g., if there are 10 files needing upload, the client will trigger the "when" of those uploads.
In terms of downloading-- the client should also have control over what types of files get downloaded first. 

E.g., if there are icon images, the client should be able to prioritize those.
Also, the client should be able to have attribute information on other files for figuring out how to prioritize their download.

Currently the client framework forces a client to always download all files from the server. This isn't tractable. It takes a long time. It may take more space locally than a user has. It isn't compatible with having the app downloda all icons first, and then large images at a later (say, on demand) time.
	
## Generally, I want it to be easier for an app to be written to use this library. Right now, it's pretty complicated.
One of these issues are dealing with different ordering of file downloads. Sharing groups can have multiple files. And those files can be downloaded in different orders. And this means an application has to deal with integrating those files into its own data in various ways depending on those download orderings. Could we unify the download of sharing groups with different sets of files? OR-- Perhaps that'll be dealt with by providing the application with control over downloading-- which we are planning to do!!
	
## I want the conflict resolution mechanism to be simpler in terms of the app's coding.
Even if we have to take some strong opinions about conflict resolution.
	
## Need to reconsider UUID collisions. 
If there is a collision, it will occur on the server. We need to be able to inform the client so it can update its records.

## Overall "master version" model-- this is constraining. 
And could use a more general model.
Some different possible levels:
file
file group-- do file groups have versions?
sharing group-- which is where I think I have it right now-- I think each sharing group has a master version.
	
## Permission model. Rethink.
I'd like to have this more general. E.g., to be able to make one file completely public.

## Redesign the view container for signin controls.
Use SwiftUI. And not just the code itself-- the UX/UI form and appearance of the controls need work for usability.

## Restructure the synchronization internals of the client. 
Right now it's too complicated, hard to test, and hard to maintain. Part of this is that there are numerous singletons being used. Part of this has to do with having the completion of one server operation cause the initiation of another-- or rather the next server operation (upload or download). This forms a complicated state machine where download states transition to upload states, transition to a commit-uploads state. Combined with failure states which require forms of rollback.

Part of this restructuring needs to take into account that, for upload at least, we'll be triggering multiple possible uploads (i.e., for a file group) effectively simultaneously. We have to make sure that the server can handle these concurrent uploads from a single client. And, once the group of uploads is completed, that a commit-uploads operation can be triggered-- and that the commit-uploads is triggered only at that point.

## Testing.
It's too hard to figure out right now if a needed test is present in the set of tests. Testing needs restructuring and simplification.

# Neebla

## Add a sharing extension. 
From other apps (e.g., Apple's photo app), upload a file or file(s).

## Add another main view which is oriented around time, and discussion threads. 
Instead of showing the images first, the discussions are displayed. And you can navigate to the related images. 

## This raises the possiblity of having multiple images associated with a single discussion thread.
