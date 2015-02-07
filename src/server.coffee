env = process.env

# Removes the temporary directory on startup.
REMOVE_TMP_ON_LOAD = env.REMOVE_TMP_ON_LOAD
if REMOVE_TMP_ON_LOAD == '1' || REMOVE_TMP_ON_LOAD == 'true'
  console.log('Removing TEMP_DIR...')
  TEMP_DIR = env.TEMP_DIR
  if TEMP_DIR
    console.log('TEMP_DIR=', TEMP_DIR)
    shell = Meteor.npmRequire('shelljs')
    path = Meteor.npmRequire('path')
    shell.rm('-rf', path.join(TEMP_DIR, '*'))
    console.log('Removed TEMP_DIR')
  else
    console.log('No TEMP_DIR set')

adapter = 'FILESYSTEM'
Adapters =
  FILESYSTEM:
    config: {}
  S3:
    config: {}

# Filesystem adapter
FILES_DIR = env.FILES_DIR
if FILES_DIR?
  Adapters.FILESYSTEM.config.path = FILES_DIR + '/cfs'

# S3 adapter
s3BucketName = env.S3_BUCKET_NAME
if s3BucketName
  adapter = 'S3'
  Adapters.S3.config.bucket = s3BucketName
  s3Region = env.S3_REGION
  Adapters.S3.config.region = s3Region if s3Region

cfsAdapter = env.CFS_ADAPTER
if cfsAdapter
  adapter = cfsAdapter

adapterArgs = Adapters[adapter]
console.log('Using cfs adapter:', adapter)
if adapter == 'FILESYSTEM'
  console.log('Using cfs directory:', (adapterArgs.config.path ? 'default path'))

# Necessary to reference the correct reference of Files.
global = @

FileUtils =

  whenUploaded: (fileId) -> Promises.runSync -> global.Files.whenUploaded(fileId)

  getReadStream: (fileId) ->
    @whenUploaded(fileId)
    item = global.Files.findOne(fileId)
    unless item
      throw new Meteor.Error(404, 'File with ID ' + fileId + ' not found.')
    item.createReadStream('files')

  getBuffer: (fileId) ->
    @whenUploaded(fileId)
    reader = @getReadStream(fileId)
    Buffers.fromStream(reader)

  writeToTempFile: (filename, data) ->
    os = Meteor.npmRequire('os')
    fs = Meteor.npmRequire('fs')
    path = Meteor.npmRequire('path')
    filePath = path.join(os.tmpdir(), filename)
    fs.writeFileSync(filePath, data)
    filePath

Meteor.methods

  'files/download/string': (id) -> FileUtils.getBuffer(id).toString()
  'files/download/json': (id) ->
    data = FileUtils.getBuffer(id).toString()
    if data == ''
      throw new Meteor.Error(400, 'Attempted to download empty JSON')
    else
      JSON.parse(data)
  'files/adapter': ->
    {adapter: adapter, args: Adapters[adapter]}
