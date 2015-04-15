templateName = 'uploadField'
TemplateClass = Template[templateName]

TemplateClass.created = ->
  @data ?= {}

# TODO(aramk) Make this logic with a Meteor Dependency somehow?
TemplateClass.rendered = ->
  name = @data.name
  collection = getCollection()

  $valueInput = getValueInput()
  $fileInput = getFileInput()
  $removeButton = getRemoveButton()

  updateState(@)
  $valueInput.change(updateState.bind(@))

  $removeButton.click =>
    $valueInput.val('')
    $fileInput.val('')
    updateState(@)

TemplateClass.events
  'change [type="file"]': (e, template) ->
    $valueInput = getValueInput()
    handleUpload({
      fileNode: e.target
      collection: getCollection()
    }).then(
      (fileObj) ->
        $valueInput.val(fileObj._id)
        updateState(template)
      (err) -> alert('File upload faied: ' + err)
    )

getCollection = (template) -> getTemplate(template).data?.collection ? Files

updateState = (template) ->
  $valueInput = getValueInput(template)
  $fileInput = getFileInput(template)
  $removeButton = getRemoveButton(template)
  $filename =  getFilename(template)

  value = $valueInput.val()
  fileObj = if value then getCollection(template).findOne(value)
  filename = fileObj?.name()
  $fileInput[if !value then 'show' else 'hide'](0)
  $removeButton[if value then 'show' else 'hide'](0)
  $filename[if filename then 'show' else 'hide'](0)
  $filename.text(filename)

getValueInput = (template) -> getTemplate(template).$('.value input')
getFileInput = (template) -> getTemplate(template).$('input[type="file"]')
getRemoveButton = (template) -> getTemplate(template).$('.remove.button')
getFilename = (template) -> getTemplate(template).$('.filename')

getTemplate = (template) -> Templates.getNamedInstance(templateName, template)

handleUpload = (args) ->
  args = _.extend({}, args)
  collection = args.collection
  unless collection
    throw new Error('No collection provided')
  fileNode = args.fileNode
  unless fileNode
    throw new Error('No file node provided')
  file = fileNode.files[0]
  unless file
    throw new Error('No file selected for uploading')
  $loader = $(fileNode).siblings('.ui.dimmer')
  onUploadStart = ->
    $loader.addClass('active')
  onUploadComplete = ->
    $loader.removeClass('active')
  onUploadStart()
  collection.upload(file).fin -> onUploadComplete()
