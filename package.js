Package.describe({
  name: 'aramk:file-upload',
  summary: 'Simple file uploads.',
  version: '0.2.5'
});

Package.on_use(function(api) {
  api.versionsFrom('METEOR@0.9.0');
  api.use([
    'coffeescript',
    'underscore',
    'aramk:q@1.0.1_1',
    'aramk:utility@0.6.0',
    'cfs:standard-packages@0.5.6',
    'cfs:filesystem@0.1.2',
    'cfs:s3@0.1.3'
  ], ['client', 'server']);
  api.addFiles([
    'src/common.coffee'
  ], ['client', 'server']);
  api.addFiles([
    'src/server.coffee'
  ], 'server');
  // Files is defined lazily once an adapter is found, so isn't an explicit import to avoid creating
  // a global variable set to undefiend.
  // api.export(['Files'], ['client', 'server']);
  api.imply('cfs:standard-packages@0.5.6');
  api.export(['FileUtils'], 'server');
});
