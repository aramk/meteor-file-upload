meteor-file-upload
==================

Simple file uploads in Meteor.

## Setup

### Packages

This package relies on the following forked packages to work correctly. Add them with Meteorite or symlink them into the `packages` directory.

[aramk/Meteor-cfs-tempstore](https://github.com/aramk/Meteor-cfs-tempstore) - Contains the fix mentioned [here](https://github.com/CollectionFS/Meteor-CollectionFS/issues/451) and [here](https://github.com/CollectionFS/Meteor-CollectionFS/issues/445#issuecomment-60778982) for uploading files on [Modulus](http://modulus.io).

[aramk/Meteor-cfs-s3.git](https://github.com/aramk/Meteor-cfs-s3.git) - Contains [this](https://github.com/aramk/Meteor-cfs-s3/commit/880d11c699c3c6922253f01ae52c6bc90c7bca75#commitcomment-8861871) pull request which fixes an issue with downloading files from S3.

### Directories

The `FILES_DIR` environment variable should be set the app files directory. `TEMP_DIR` should be the temporary files directory. If the `REMOVE_TMP_ON_LOAD` environment variable is set to a "true", the temporary directory will be cleared on server startup.

## Modulus

Set an environment variable `FILES_DIR="/app-storage"` in the Modulus app administration.
