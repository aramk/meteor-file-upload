StoreConstructors =
  FILESYSTEM: FS.Store.FileSystem
  S3: FS.Store.S3

# Necessary to ensure our definition below uses the package-scope reference.
global = @

Meteor.startup ->

  Meteor.call 'files/adapter', (err, result) ->

    console.log('File adapter:', result)
    adapterArgs = result.args
    adapter = result.adapter
    StoreClass = StoreConstructors[adapter]
    Files = global.Files = new FS.Collection 'files', stores: [
      new StoreClass('files', adapterArgs.config)
    ]
    Files.allow
      download: Collections.allow
      insert: Collections.allow
      update: Collections.allow
      remove: Collections.allow

    if Meteor.isServer
      Meteor.publish 'files', -> Files.find()
    else
      Meteor.subscribe('files')

    # File IDs to deferred promises containing their data.
    fileCache = {}

    download = (method, fileId) ->
      unless fileId?
        throw new Error('No file ID given')
      fileDf = Q.defer()
      cacheDf = fileCache[fileId]
      unless cacheDf
        cacheDf = fileCache[fileId] = Q.defer()
        Meteor.call method, fileId, (err, data) ->
          if err
            cacheDf.reject(err)
          else
            cacheDf.resolve(data)
      cacheDf.promise.then(
        (data) -> fileDf.resolve(Setter.clone(data))
        fileDf.reject
      )
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
        # TODO(aramk) Remove timeout and use an event callback.
        timerHandler = Meteor.bindEnvironment ->
          progress = fileObj.uploadProgress()
          uploaded = fileObj.isUploaded()
          if uploaded
            clearTimeout(handle)
            df.resolve(fileObj)
        handle = setInterval timerHandler, 1000
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
