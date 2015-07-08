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
      }, args)
      globalName = args.globalName
      collection = new FS.Collection(id, args)
      collection.name = id
      collection.allow
        download: Collections.allow
        insert: Collections.allow
        update: Collections.allow
        remove: Collections.allow
      bindMethods(globalName, collection)
      global[globalName] = collection

      unless args.noPublish == true
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
      file = collection.findOne(fileId)
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

    download: (fileId) -> download('files/download/string', fileId, collectionName)

    downloadJson: (fileId) -> download('files/download/json', fileId, collectionName)

    upload: (obj, options) ->
      Logger.info('Uploading file', obj, options)
      df = Q.defer()
      onFileObj = (fileObj) -> df.resolve collection.whenUploaded(fileObj._id)
      unless options?.useExisting == false
        Logger.debug('Checking for existing file copy...')
        stats = @getFileStats(obj)
        name = stats.name
        size = stats.size
        if name? && size?
          fileObj = collection.findOne({'original.name': name, 'original.size': size})
      if fileObj
        Logger.info('Reusing existing file', fileObj._id)
        onFileObj(fileObj)
      else
        collection.insert obj, Meteor.bindEnvironment (err, fileObj) ->
          if err then df.reject(err) else onFileObj(fileObj)
      df.promise

    getFileStats: (obj) ->
      if obj instanceof FS.File
        name = obj.name()
        size = obj.size()
      else if Meteor.isClient && obj instanceof File
        name = obj.name
        size = obj.size ? obj.fileSize
      {name: name, size: size}

  if Meteor.isClient

    _.extend collection,

      toBlob: (fileId) ->
        # NOTE: Only works with string data. Use downloadInBrowser() to download any type of file.
        file = collection.findOne(fileId)
        collection.download(fileId).then (data) ->
          Blobs.fromString(data, type: file.type())

      downloadInBrowser: (fileId, args) ->
        args = Setter.merge({
          blob: false
        }, args)
        file = collection.findOne(fileId)
        if args.blob
          blob = @toBlob(fileId)
          Blobs.downloadInBrowser(blob, file.name())
        else
          Window.downloadFile(file.url())

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
