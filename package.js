Package.describe({
  name: 'aramk:file-upload',
  summary: 'Simple file uploads.',
  version: '0.1.2'
});

Package.on_use(function(api) {
  api.versionsFrom('METEOR@0.9.0');
  api.use(['coffeescript', 'underscore', 'aramk:utility@0.4.2', 'cfs:standard-packages@0.5.3',
    'cfs:filesystem@0.1.1', 'cfs:s3@0.1.1'], ['client', 'server']);
  api.add_files(['src/common.coffee'], ['client', 'server']);
  api.add_files(['src/server.coffee'], 'server');
  api.export(['Files'], ['client', 'server']);
  api.export(['Files', 'FileUtils'], 'server');
});
