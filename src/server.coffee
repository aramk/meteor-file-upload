env = process.env

TEMP_DIR = env.TEMP_DIR

# Removes the temporary directory on startup.
REMOVE_TMP_ON_LOAD = env.REMOVE_TMP_ON_LOAD
if REMOVE_TMP_ON_LOAD == '1' || REMOVE_TMP_ON_LOAD == 'true'
  console.log('Removing TEMP_DIR...')
  if TEMP_DIR?
    console.log('TEMP_DIR=', TEMP_DIR)
    shell = Meteor.npmRequire('shelljs')
    path = Meteor.npmRequire('path')
    shell.rm('-rf', path.join(TEMP_DIR, '*'))
    console.log('Removed TEMP_DIR')
  else
    console.log('No TEMP_DIR set')

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

# Necessary to reference the correct reference of Files.
global = @

getCollection = (name) ->
  name ?= 'Files'
  collection = Collections.get(name)
  unless collection then throw new Error('Cannot find collection with name ' + name)
  collection

_.extend FileUtils,

  whenUploaded: (fileId, collectionName) ->
    Promises.runSync -> getCollection(collectionName).whenUploaded(fileId)

  getReadStream: (fileId, collectionName) ->
    @whenUploaded(fileId, collectionName)
    item = getCollection(collectionName).findOne(_id: fileId)
    unless item
      throw new Meteor.Error(404, 'File with ID ' + fileId + ' not found.')
    item.createReadStream('files')

  getBuffer: (fileId, collectionName) ->
    @whenUploaded(fileId, collectionName)
    reader = @getReadStream(fileId, collectionName)
    Buffers.fromStream(reader)

  writeToTempFile: (filename, data) ->
    os = Meteor.npmRequire('os')
    fs = Meteor.npmRequire('fs')
    path = Meteor.npmRequire('path')
    filePath = path.join(os.tmpdir(), filename)
    fs.writeFileSync(filePath, data)
    filePath

  getAdapters: -> Setter.clone(Adapters)

Meteor.methods

  'files/download/string': (fileId, collectionName) ->
    FileUtils.getBuffer(fileId, collectionName).toString()
  'files/download/json': (fileId, collectionName) ->
    data = FileUtils.getBuffer(fileId, collectionName).toString()
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
