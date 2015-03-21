# Load all required libraries.
gulp = require 'gulp'
gutil = require 'gulp-util'
coffee = require 'gulp-coffee'
istanbul = require 'gulp-istanbul'
mocha = require 'gulp-mocha'
watch = require 'gulp-watch'
plumber = require 'gulp-plumber'
# jsdoc2md = require 'gulp-jsdoc-to-markdown'
jsdoc2md = require("jsdoc-to-markdown")
concat = require("gulp-concat")
fs = require("fs")
# markdox = require("gulp-markdox")

onError = (err) ->
  gutil.beep()
  gutil.log err.stack

gulp.task 'coffee', ->
  gulp.src 'src/**/*.coffee'
    .pipe plumber({errorHandler: onError}) # Pevent pipe breaking caused by errors from gulp plugins
    .pipe coffee({bare: true})
    .pipe gulp.dest './lib/'

gulp.task 'test', ['coffee'], ->
  gulp.src ['lib/**/*.js']
    .pipe(istanbul()) # Covering files
    .pipe(istanbul.hookRequire()) # Force `require` to return covered files
    .on 'finish', ->
      gulp.src(['test/**/*.spec.coffee'])
        .pipe mocha
          reporter: 'spec'
          compilers: 'coffee:coffee-script'
          timeout: 3000
        .pipe istanbul.writeReports() # Creating the reports after tests run

gulp.task "doc", ->
  src = "lib/**/*.js"
  dest = "README.md"
  options = { template: 'README.hbs'}

  gutil.log("writing documentation to " + dest)
  return jsdoc2md.render(src, options)
      .on "error", (err) ->
        gutil.log(gutil.colors.red("jsdoc2md failed"), err.message)
      .pipe(fs.createWriteStream(dest))

gulp.task 'watch', ->
  gulp.watch 'src/**/*.coffee', ['coffee']

gulp.task 'default', ['coffee', 'watch']
