os = Npm.require('os')
fs = Npm.require('fs')
path = Npm.require('path')
mime = Npm.require('mime')
env = process.env

TEMP_DIR = env.TEMP_DIR

# Removes the temporary directory on startup.
REMOVE_TMP_ON_LOAD = env.REMOVE_TMP_ON_LOAD
if REMOVE_TMP_ON_LOAD == '1' || REMOVE_TMP_ON_LOAD == 'true'
  Logger.info('Removing TEMP_DIR...')
  if TEMP_DIR?
    Logger.info('TEMP_DIR=', TEMP_DIR)
    shell = Npm.require('shelljs')
    path = Npm.require('path')
    shell.rm('-rf', path.join(TEMP_DIR, '*'))
    Logger.info('Removed TEMP_DIR')
  else
    Logger.info('No TEMP_DIR set')

# Default to filesystem for storage.
Adapters =
  FILESYSTEM:
    config: {}

if TEMP_DIR?
  Adapters._tempstore =
    adapter: 'FILESYSTEM'
    config:
      internal: true
      path: TEMP_DIR

# Filesystem adapter
FILES_DIR = env.FILES_DIR
if FILES_DIR?
  if FILES_DIR == '0'
    delete Adapters.FILESYSTEM
  else
    Adapters.FILESYSTEM.config.path = FILES_DIR + '/cfs'

# S3 adapter
s3BucketName = env.S3_BUCKET_NAME
if s3BucketName
  s3Region = env.S3_REGION
  Adapters.S3 =
    config:
      bucket: s3BucketName
  Adapters.S3.config.region = s3Region if s3Region

if env.CFS_FILESYSTEM == '0'
  delete Adapters.FILESYSTEM
  Logger.info('Disabling filesystem for CFS')

# Necessary to reference the correct reference of Files.
global = @

getCollection = (arg) ->
  arg ?= 'Files'
  collection = Collections.get(arg)
  unless collection then throw new Error('Cannot find collection: ' + arg)
  collection

_.extend FileUtils,

  whenUploaded: (fileId, collectionName) ->
    Promises.runSync -> getCollection(collectionName).whenUploaded(fileId)

  getReadStream: (fileId, collectionName, options) ->
    @whenUploaded(fileId, collectionName)
    collection = getCollection(collectionName)
    file = collection.findOne(_id: fileId)
    unless file
      throw new Meteor.Error(404, 'File with ID ' + fileId + ' not found.')
    collectionId = Collections.getName(collection)
    file.createReadStream(collectionId, options)

  getBuffer: (fileId, collectionName, options) ->
    @whenUploaded(fileId, collectionName)
    reader = @getReadStream(fileId, collectionName, options)
    Buffers.fromStream(reader)

  writeToTempFile: (filename, data) ->
    filePath = path.join(os.tmpdir(), filename)
    fs.writeFileSync(filePath, data)
    filePath

  getAdapters: -> Setter.clone(Adapters)

Meteor.methods

  'files/download/string': (fileId, collectionName, options) ->
    Logger.debug('Downloading file:', collectionName, fileId, options)
    return unless @userId
    @unblock()
    data = FileUtils.getBuffer(fileId, collectionName, options).toString()
    Logger.debug('Returning file string:', collectionName, fileId, data.length)
    data

  'files/download/json': (fileId, collectionName, options) ->
    Logger.debug('Downloading file:', collectionName, fileId, options)
    return unless @userId
    @unblock()
    data = FileUtils.getBuffer(fileId, collectionName, options).toString()
    Logger.debug('Returning file JSON:', collectionName, fileId, data.length)
    if data == ''
      throw new Meteor.Error(400, 'Attempted to download empty JSON')
    else
      JSON.parse(data)

  'files/adapters': ->
    # Only return the name of the adapters to prevent access to confidential settings on the client.
    adapters = {}
    _.each Adapters, (args, id) ->
      adapters[id] = {}
    adapters

  'files/query': (args) ->
    return unless @userId
    getCollection(args.collection).find(args.selector).map (file) -> file._id

  'files/upload/url': (url, args) ->
    return unless @userId
    @unblock()
    collection = getCollection(args.collection)
    buffer = Request.buffer(method: 'GET', uri: url)
    file = new FS.File()
    fileName = Paths.basename(url)
    type = mime.lookup(fileName)
    file.attachData(buffer, {type: type})
    fileObj = collection.insert(file)
    fileObj._id
