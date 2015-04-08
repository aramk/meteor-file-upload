Package.describe({
  name: 'aramk:file-upload',
  summary: 'Simple file uploads.',
  version: '0.3.1'
});

Package.on_use(function(api) {
  api.versionsFrom('METEOR@0.9.0');
  api.use([
    'coffeescript',
    'underscore',
    'aramk:q@1.0.1_1',
    'aramk:utility@0.6.0',
    'cfs:standard-packages@0.5.7',
    'cfs:filesystem@0.1.2',
    'cfs:tempstore@0.1.5',
    'cfs:s3@0.1.3'
  ], ['client', 'server']);
  api.addFiles([
    'src/common.coffee'
  ], ['client', 'server']);
  api.addFiles([
    'src/server.coffee'
  ], 'server');
  api.imply('cfs:standard-packages@0.5.7');
  api.export([
    'FileUtils'
  ], ['client', 'server']);
});
