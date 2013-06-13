fs      = require "fs"
os      = require "os"
coffee  = require "coffee-script"
path    = require "path"

fs.existsSync ?= path.existsSync

pistachios = /\{(\w*)?(\#\w*)?((?:\.\w*)*)(\[(?:\b\w*\b)(?:\=[\"|\']?.*[\"|\']?)\])*\{([^{}]*)\}\s*\}/g

compileDebug = (path, source, error)->
  data = source.toString()
  if error.location
    {first_line, last_line, first_column, last_column} = error.location
    lines = data.split os.EOL
    trace = lines.slice(first_line, last_line+1).join os.EOL
    point = ""
    for i in [0..last_column]
      if i < first_column then point+=" " else point+="^"
    point+= " #{error.message}"

  first_line++; last_line++;
  spaces = Array((first_line+"").length+1).join " "
  curr = first_line
  prev = first_line - 1
  next = first_line + 1

  previous_line = if first_line > 1 then "#{prev}   #{lines[prev-1]}" else ""
  next_line = if lines.length > next then "#{next}  #{lines[next-1]}" else ""
  """
  at #{path} line #{first_line}:#{last_line} column #{first_column}:#{last_column}

  #{previous_line}
  #{curr}   #{trace}
  #{spaces}   #{point}
  #{next_line}
  """

module.exports = ()->

  [bin, file, appPath] = process.argv

  appPath or= process.cwd()
 
  manifestPath = "#{path.resolve appPath}/manifest.json"

  try
    manifest = JSON.parse fs.readFileSync path.join appPath, "manifest.json"
  catch error
    if error.errno is 34
      console.log "Manifest file does not exists: #{manifestPath}"
    else
      console.log "Manifest file seems corrupted: #{manifestPath}"
    process.exit error.errno or 3

  files = manifest?.source?.blocks?.app?.files
  unless files
    console.log "The object 'source.blocks.app.files' is not found in manifest file."
    process.exit 3

  unless Array.isArray files
    console.log "The object 'source.blocks.app.files' must be array in manifest file."
    process.exit 3

  source = ""

  for file in files
    file = path.normalize (path.join appPath, file)  if appPath

    if /\.coffee/.test file
      try
        data = fs.readFileSync file
      catch error
        console.log "The required file not found: #{file}"
        process.exit error.errno
      try
        compiled = coffee.compile data.toString(), bare: true
      catch error
        console.log "Compile Error: #{error.message}"
        console.log compileDebug(file, data, error)
        process.exit 4

    else if /\.js/.test file
      try
        compiled = fs.readFileSync(file).toString()
      catch error
        console.log error
        process.exit 1

    block = """
    /* BLOCK STARTS: #{file} */
    #{compiled}
    """
    block = block.replace pistachios, (pistachio)-> pistachio.replace /\@/g, 'this.'
    source += block

  mainSource = """
  /* Compiled by kdc on #{(new Date()).toString()} */
  (function() {
  /* KDAPP STARTS */
  #{source}
  /* KDAPP ENDS */
  }).call();
  """
  fs.writeFileSync (path.join appPath, "index.app.js"), mainSource
  console.log "Application has been compiled!"
