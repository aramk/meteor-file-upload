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
        throw new Error('No file ID given')
      fileDf = fileCache[fileId]
      unless fileDf
        fileDf = fileCache[fileId] = Q.defer()
        Meteor.call method, fileId, (err, data) ->
          if err
            fileDf.reject(err)
          else
            fileDf.resolve(data)
      fileDf.promise.then(
        (data) -> Setter.clone(data)
      )

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
