StoreConstructors =
  FILESYSTEM: FS.Store.FileSystem
  S3: FS.Store.S3

# Necessary to ensure our definition below uses the package-scope reference.
global = @

# A map of collection IDs to promises which are resolved once they are set up.
collectionPromises = {}

# File IDs to deferred promises containing their data.
fileCache = {}

FILE_COLLECTION_ID = 'files'

FileUtils =

  ready: (name) ->
    name ?= FILE_COLLECTION_ID
    Q(collectionPromises[name])

  createCollection: (id, args) ->
    df = Q.defer()
    collectionPromises[id] = df.promise
    # Wait for startup to complete to ensure collections can be defined.
    Meteor.startup => df.resolve @_createCollection(id, args)
    df.promise

  _createCollection: (id, args) ->
    df = Q.defer()
    adapterPromise = Q.when(@getAdapters())
    adapterPromise.fail (err) -> Logger.error('Could not set up CFS adapters', err)
    adapterPromise.then Meteor.bindEnvironment (result) =>
      tempStoreArgs = result._tempstore
      if tempStoreArgs
        delete result._tempstore
        if Meteor.isServer
          createTempStore(tempStoreArgs)

      stores = []
      _.each result, (args, adapterId) ->
        stores.push createStore(adapterId, id + '-' + adapterId, args.config)
      
      args = _.extend({
        stores: stores
        globalName: Strings.toTitleCase(id)
        publish: true
      }, args)
      globalName = args.globalName
      collection = new FS.Collection(id, args)
      collection.name = id
      allowUser = (userId, doc) -> userId?
      collection.allow
        download: allowUser
        insert: allowUser
        update: allowUser
        remove: allowUser
      bindMethods(globalName, collection)
      global[globalName] = collection

      if args.publish
        if Meteor.isServer
          Meteor.publish id, -> if @userId then collection.find() else []
        else
          Meteor.subscribe(id)

      df.resolve(collection)
    df.promise

if Meteor.isClient

  _.extend FileUtils,
    getAdapters: ->  Promises.serverMethodCall('files/adapters')

bindMethods = (collectionName, collection) ->

  _.extend collection,

    whenUploaded: (fileId) ->
      df = Q.defer()
      file = collection.findOne(_id: fileId)
      unless file
        return Q.reject('No file with ID ' + fileId + ' found.')
      # TODO(aramk) Remove timeout and use an event callback.
      timerHandler = Meteor.bindEnvironment ->
        progress = file.uploadProgress()
        uploaded = file.isUploaded()
        Logger.debug('Waiting for file upload to complete...', fileId, progress, uploaded)
        if uploaded
          Logger.debug('File upload is complete', fileId, progress)
          Meteor.clearInterval(handle)
          df.resolve(file)
      handle = Meteor.setInterval timerHandler, 1000
      timerHandler()
      df.promise

    download: (fileId) -> download('files/download/string', fileId, collectionName)

    downloadJson: (fileId) -> download('files/download/json', fileId, collectionName)

    # Uploads the given file to the collection.
    #  * `file` - Either an `FS.File`, `File`, or URL string.
    #  * `options.useExisting` - Whether to attempt to use an existing copy of the given file
    #                            instead of uploading a new copy. Defaults to true.
    # Returns a promise containing uploaded or existing `FS.File` instance.
    upload: (file, options) ->
      df = Q.defer()
      onFileId = (fileId) -> df.resolve collection.whenUploaded(fileId)
      unless options?.useExisting == false
        Logger.debug('Checking for existing file copy...')
        fileObj = @getExistingCopy(file)
      if fileObj
        Logger.debug('Reusing existing file', fileObj._id)
        onFileId(fileObj._id)
      else
        Logger.debug('Uploading file', file, options)
        if Paths.isUrl(file)
          Meteor.call 'files/upload/url', file, {collection: collectionName}, (err, fileId) ->
            if err then df.reject(err) else onFileId(fileId)
        else
          collection.insert file, Meteor.bindEnvironment (err, fileObj) ->
            if err then df.reject(err) else onFileId(fileObj._id)
      df.promise

    getExistingCopy: (file) ->
      stats = @getFileStats(file)
      name = stats.name
      size = stats.size
      if name? && size?
        selector = {'original.name': name, 'original.size': size}
      else if url?
        selector = {'original.url': url}
      if selector then collection.findOne(selector)

    getFileStats: (file) ->
      if Paths.isUrl(file)
        name = Paths.basename(file)
        url = file
      if file instanceof FS.File
        name = file.name()
        size = file.size()
      else if Meteor.isClient && file instanceof File
        name = file.name
        size = file.size ? file.fileSize
      {name: name, size: size, url: url}

  if Meteor.isClient

    _.extend collection,

      toBlob: (fileId) ->
        # NOTE: Only works with string data. Use downloadInBrowser() to download any type of file.
        file = collection.findOne(_id: fileId)
        collection.download(fileId).then (data) ->
          Blobs.fromString(data, type: file.type())

      downloadInBrowser: (fileId, args) ->
        args = Setter.merge({
          blob: false
        }, args)
        file = collection.findOne(_id: fileId)
        unless file then return Logger.error('File not found: ' + fileId)
        Logger.info 'Downloading file', fileId, file
        if args.blob
          @toBlob(fileId).then (blob) -> Blobs.downloadInBrowser(blob, file.name())
          return
        # Wait for the file to be synced to the client and the URL to be propagated.
        handle = null
        handler = ->
          file = collection.findOne(_id: fileId)
          if file?.url()
            clearInterval(handle)
            Window.downloadFile(file.url())
        handle = setInterval handler, 1000
        handler()

if Meteor.isServer
  createTempStore = _.once (args) ->
    FS.TempStore.Storage = createStore(args.adapter, '_tempstore', args.config)

Meteor.startup ->
  FileUtils.createCollection(FILE_COLLECTION_ID)

####################################################################################################
# AUXILIARY
####################################################################################################

createStore = (adapterId, storeId, config) ->
  StoreClass = StoreConstructors[adapterId]
  store = new StoreClass(storeId, config)
  Logger.info('Created CFS store', adapterId, storeId)
  store

download = (method, fileId, collectionName) ->
  unless fileId?
    return Q.reject('No file ID given')
  fileDf = fileCache[method]?[fileId]
  unless fileDf
    fileIdCache = fileCache[method] ?= {}
    fileDf = fileIdCache[fileId] = Q.defer()
    _download(method, fileId, collectionName, 10)
  fileDf.promise.then(
    (data) -> Setter.clone(data)
  )

_download = (method, fileId, collectionName, triesLeft) ->
  fileDf = fileCache[method][fileId]
  if triesLeft <= 0
    fileDf.reject('Could not download file ' + fileId + ' - no tries left.')
    return
  callback = (err, data) ->
    unless err? || data?
      # TODO(aramk) For some reason, the callback can be invoked even though the meteor method
      # was never called. If this is the case, re-run the download method until we get some
      # actual data back.
      _.delay(
        -> _download(method, fileId, collectionName, triesLeft - 1)
        1000
      )
    else if err
      fileDf.reject(err)
    else
      fileDf.resolve(data)
  Meteor.call(method, fileId, collectionName, callback)
