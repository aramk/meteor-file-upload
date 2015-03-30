StoreConstructors =
  FILESYSTEM: FS.Store.FileSystem
  S3: FS.Store.S3

# Necessary to ensure our definition below uses the package-scope reference.
global = @

Meteor.startup ->

  getAdapters = ->
    if Meteor.isServer
      Q.when(FileUtils.getAdapters())
    else
      Promises.serverMethodCall('files/adapters')

  promise = getAdapters()
  promise.fail (err) ->
    Logger.error('Could not set up CFS adapters', err)

  promise.then Meteor.bindEnvironment (result) ->
    stores = []
    _.each result, (args, id) ->
      StoreClass = StoreConstructors[id]
      stores.push new StoreClass(id, args.config)
    Files = global.Files = new FS.Collection 'files', stores: stores
    Files.allow
      download: Collections.allow
      insert: Collections.allow
      update: Collections.allow
      remove: Collections.allow

    if Meteor.isServer
      Meteor.publish 'files', -> Files.find()
    else
      Meteor.subscribe('files')

    Files.whenUploaded = (fileId) ->
      df = Q.defer()
      file = Files.findOne(fileId)
      unless file
        return Q.reject('No file with ID ' + fileId + ' found.')
      # TODO(aramk) Remove timeout and use an event callback.
      timerHandler = Meteor.bindEnvironment ->
        progress = file.uploadProgress()
        uploaded = file.isUploaded()
        if uploaded
          clearTimeout(handle)
          df.resolve(file)
      handle = setInterval timerHandler, 1000
      df.promise

    # File IDs to deferred promises containing their data.
    fileCache = {}

    download = (method, fileId) ->
      unless fileId?
        return Q.reject('No file ID given')
      fileDf = fileCache[fileId]
      unless fileDf
        fileDf = fileCache[fileId] = Q.defer()
        _download(method, fileId, 10).then(fileDf.resolve, fileDf.reject)
      fileDf.promise.then(
        (data) -> Setter.clone(data)
      )

    _download = (method, fileId, triesLeft) ->
      unless fileId?
        return Q.reject('No file ID given')
      if triesLeft <= 0
        return Q.reject('Could not download file ' + fileId + ' - no tries left.')
      if fileDf
        return fileDf.promise
      fileDf = Q.defer()
      callback = (err, data) ->
        unless err? || data?
          # TODO(aramk) For some reason, the callback can be invoked even though the meteor method
          # was never called. If this is the case, re-run the download method until we get some
          # actual data back.
          _.delay(
            -> _download(method, fileId, triesLeft - 1).then(fileDf.resolve, fileDf.reject)
            1000
          )
        else if err
          fileDf.reject(err)
        else
          fileDf.resolve(data)
      Meteor.call(method, fileId, callback)
      fileDf.promise

    Files.download = (fileId) -> download('files/download/string', fileId)
    Files.downloadJson = (fileId) -> download('files/download/json', fileId)

    Files.upload = (obj) ->
      console.log('Uploading file', obj)
      df = Q.defer()
      Files.insert obj, (err, fileObj) ->
        if err
          df.reject(err)
          return
        Files.whenUploaded(fileObj._id).then(df.resolve, df.reject)
      df.promise

    if Meteor.isClient

      Files.toBlob = (fileId) ->
        file = Files.findOne(fileId)
        Files.download(fileId).then (data) ->
          Blobs.fromString(data, type: file.type())

      Files.downloadInBrowser = (fileId) ->
        file = Files.findOne(fileId)
        Files.toBlob(fileId).then (blob) ->
          Blobs.downloadInBrowser(blob, file.name())
