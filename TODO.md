# TODO

## Sign-in flow with an invitation.
I've not yet taken this into account with the new sign-in packages.

##  func completeSignInProcess(autoSignIn:Bool)
I've also not implemented this in the iOSFacebook package. It wasn't appropriate for this location.

I want to check if this exact piece of code has been repeated in the other sign-in packages.

Where should this go? In the SignInManager?

## Don't allow the user to sign in as a different user.
i.e., if they have signed as one user, and downloaded data, and then sign-out and try to sign in as a different user.

## Need work and testing on silent-sign in
l.e., auto sign in

## Put ServerResponseCheck back

## Put checkForNetworkAndReport ??

## DropboxSavedCreds has changed and won't read data properly from NSUserDefaults.

## Why is the ServerAPI addUser only using a sharingGroupUUID if there is a cloud folder?
Answer: I believe this was an error in the code. addUser always needs to create a sharing group.

## Where is the retry mechanism if the access token need to be refreshed?

## Why does an access token come back from the API checkCreds call? 

## Get rid of undeletion.
Take a stronger stance. Simplify.

## Upload gone not in upload yet.
Why does the gone reason come back in the body where the rest of the response result comes back in the header. See ServerAPI upload.

## Need to put Hashing.hashOf in specific cloud storage libraries

## contentsChangedOnServer needs documentation in download.
