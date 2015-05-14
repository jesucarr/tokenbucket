# Load all required libraries.
gulp = require 'gulp'
gutil = require 'gulp-util'
coffee = require 'gulp-coffee'
istanbul = require 'gulp-istanbul'
mocha = require 'gulp-mocha'
plumber = require 'gulp-plumber'
concat = require 'gulp-concat'
fs = require 'fs'
coveralls = require 'gulp-coveralls'
gulpJsdoc2md = require 'gulp-jsdoc-to-markdown'

onError = (err) ->
  gutil.beep()
  gutil.log err.stack

gulp.task 'coffee', ->
  gulp.src 'src/**/*.coffee'
    .pipe plumber({errorHandler: onError}) # Pevent pipe breaking caused by errors from gulp plugins
    .pipe coffee({bare: true})
    .pipe gulp.dest './lib/'

gulp.task 'test', ['coffee'], ->
  gulp.src 'lib/**/*.js'
    .pipe istanbul() # Covering files
    .pipe istanbul.hookRequire() # Force `require` to return covered files
    .on 'finish', ->
      gulp.src 'test/**/*.spec.coffee'
        .pipe mocha
          reporter: 'spec'
          compilers: 'coffee:coffee-script'
        .pipe istanbul.writeReports() # Creating the reports after tests run

gulp.task 'coveralls', ->
  gulp.src 'coverage/lcov.info'
    .pipe coveralls()

gulp.task 'doc', ->
  gulp.src 'lib/**/*.js'
    .pipe concat('README.md')
    .pipe gulpJsdoc2md({template: fs.readFileSync('README.hbs', 'utf8'), 'param-list-format': 'list'})
    .on 'error', (err) ->
      gutil.log 'jsdoc2md failed:', err.message
    .pipe gulp.dest('.')

gulp.task 'watch', ->
  gulp.watch 'src/**/*.coffee', ['coffee']

gulp.task 'default', ['coffee', 'watch']
