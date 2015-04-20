'use strict'
chai = require 'chai'
sinon = require 'sinon'
chai.use require 'sinon-chai'
chai.use require 'chai-as-promised'
expect = chai.expect

Promise = require 'bluebird'

# Using the compiled JavaScript file here to be sure that the module works
TokenBucket = require '../lib/tokenbucket'

bucket = null
clock = null

# Helper function that checks that the removal happened inmediately or after the supposed time, and that it leaves the right amount of tokens
checkRemoval = ({tokensRemove, time, tokensLeft, done, clock, parentTokensLeft, nextTickScheduler}) ->
  if nextTickScheduler
    Promise.setScheduler (fn) ->
      process.nextTick fn
  bucket.removeTokens(tokensRemove)
    .then (remainingTokens) ->
      expect(bucket.tokensLeft, 'bucket.tokensLeft').eql tokensLeft if tokensLeft?
      if parentTokensLeft
        expect(bucket.parentBucket.tokensLeft, 'bucket.parentBucket.tokensLeft').eql parentTokensLeft
      if bucket.parentBucket
        message = 'remaining with parent: ' + bucket.tokensLeft + ', ' + bucket.parentBucket.tokensLeft + ', ' + remainingTokens
        expect(Math.min(bucket.tokensLeft, bucket.parentBucket.tokensLeft) == remainingTokens, message).true
      else
        message = 'remaining ' + remainingTokens + ', ' + bucket.tokensLeft
        expect(bucket.tokensLeft == remainingTokens, message).true
      done()
    .catch (err) ->
      done(err)
  # Promises with enough tokens get resolved without any clock tick
  if time
    done = sinon.spy(done)
    clock.tick(time - 1)
    expect(done).not.called
    clock.tick(1)

describe 'a default tokenbucket', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    bucket = new TokenBucket()
  afterEach ->
    clock.restore()
  it 'is initialized with the right values', ->
    expect(bucket.size).eql 1
    expect(bucket.tokensToAddPerInterval).eql 1
    expect(bucket.interval).eql 1000
    expect(bucket.tokensLeft).eql 1
    expect(bucket.lastFill).eql 0 # Fake timer without any tick
    expect(bucket.spread).undefined
    expect(bucket.redis).undefined
    expect(bucket.parentBucket).undefined
  describe 'when configuring the instance', ->
    parentBucket = new TokenBucket
      size: 10
    beforeEach (done) ->
      bucket.size = 5
      bucket.tokensToAddPerInterval = 2
      bucket.interval = 500
      bucket.tokensLeft = 3
      bucket.lastFill = +new Date() - 250 # Fake timer at 0ms minus 250ms
      bucket.spread = true
      bucket.redis =
        bucketName: 'bucket1'
        redisClient: 'fakeRedisClient'
      bucket.parentBucket = parentBucket
      done()
    it 'has the right values', ->
      expect(bucket.size).eql 5
      expect(bucket.tokensToAddPerInterval).eql 2
      expect(bucket.interval).eql 500
      expect(bucket.tokensLeft).eql 3
      expect(bucket.lastFill).eql -250
      expect(bucket.spread).true
      expect(bucket.redis).eql
        bucketName: 'bucket1'
        redisClient: 'fakeRedisClient'
      expect(bucket.parentBucket).eql parentBucket
    it 'works as expected with the configured instance', (done) ->
      expect(bucket.tokensLeft).eql 3
      checkRemoval
        tokensLeft: 3 # had 3 tokens left, plus 1 token (2 tokens per interval / half interval passed added evenly = 1 token), makes 4 tokens, minus 1 token removed = 3
        done: done

  describe 'removeTokens called without parameter', ->
    it 'removes 1 token instantly and leaves 0 tokens', (done) ->
      checkRemoval
        tokensLeft: 0
        done: done
  describe 'trying to remove more tokens than the bucket size', ->
    it 'rejects the promise with the right error', (done) ->
      bucket.removeTokens(2).catch (err) ->
        expect(err instanceof Error).true
        expect(err.name).eql 'NotEnoughSize'
        expect(err.message).eql 'Requested tokens (2) exceed bucket size (1)'
        done()

describe 'a tokenbucket with redis options', ->
  it 'removes redis if bucketName is not set', ->
    bucket = new TokenBucket
      redis:
        redisClient: 'fakeRedisClient'
        redisClientConfig:
          port: 1000
    expect(bucket.redis).undefined
  it 'removes redisClientConfig if redisClient is set', ->
    bucket = new TokenBucket
      redis:
        bucketName: 'bucket1'
        redisClient: 'fakeRedisClient'
        redisClientConfig:
          port: 1000
    expect(bucket.redis.redisClientConfig).undefined
  it 'sets redisClientConfig defaults', ->
    bucket = new TokenBucket
      redis:
        bucketName: 'bucket1'
    expect(bucket.redis.redisClientConfig.port).eql 6379
    expect(bucket.redis.redisClientConfig.host).eql '127.0.0.1'
    expect(bucket.redis.redisClientConfig.unixSocket).undefined
    expect(bucket.redis.redisClientConfig.options).exists
    bucket.redis.redisClient.end()
  it 'sets redisClientConfig as defined', ->
    bucket = new TokenBucket
      redis:
        bucketName: 'bucket1'
        redisClientConfig:
          port: 6379
          host: 'localhost'
          options:
            max_attempts: 10
    expect(bucket.redis.redisClientConfig.port).eql 6379
    expect(bucket.redis.redisClientConfig.host).eql 'localhost'
    expect(bucket.redis.redisClientConfig.unixSocket).undefined
    expect(bucket.redis.redisClientConfig.options.max_attempts).eql 10
    bucket.redis.redisClient.end()
  it 'sets unixSocket if defined, and throws and error for the non existing socket', (done) ->
    bucket = new TokenBucket
      redis:
        bucketName: 'bucket1'
        redisClientConfig:
          unixSocket: '/tmp/fakeredis.sock'
    bucket.redis.redisClient.on 'error', (err) ->
      expect(err instanceof Error).true
      bucket.redis.redisClient.end()
      done()

describe 'a tokenbucket initialized with interval string', ->
  describe 'when string is second', ->
    beforeEach ->
      bucket = new TokenBucket
        interval: 'second'
    it 'is initialized with the right interval', ->
      expect(bucket.interval).eql 1000
  describe 'when string is minute', ->
    beforeEach ->
      bucket = new TokenBucket
        interval: 'minute'
    it 'is initialized with the right interval', ->
      expect(bucket.interval).eql 1000 * 60
  describe 'when string is hour', ->
    beforeEach ->
      bucket = new TokenBucket
        interval: 'hour'
    it 'is initialized with the right interval', ->
      expect(bucket.interval).eql 1000 * 60 * 60
  describe 'when string is day', ->
    beforeEach ->
      bucket = new TokenBucket
        interval: 'day'
    it 'is initialized with the right interval', ->
      expect(bucket.interval).eql 1000 * 60 * 60 * 24

describe 'a tokenbucket initialized with maxWait string', ->
  describe 'when string is second', ->
    beforeEach ->
      bucket = new TokenBucket
        maxWait: 'second'
    it 'is initialized with the right interval', ->
      expect(bucket.maxWait).eql 1000
  describe 'when string is minute', ->
    beforeEach ->
      bucket = new TokenBucket
        maxWait: 'minute'
    it 'is initialized with the right interval', ->
      expect(bucket.maxWait).eql 1000 * 60
  describe 'when string is hour', ->
    beforeEach ->
      bucket = new TokenBucket
        maxWait: 'hour'
    it 'is initialized with the right interval', ->
      expect(bucket.maxWait).eql 1000 * 60 * 60
  describe 'when string is day', ->
    beforeEach ->
      bucket = new TokenBucket
        maxWait: 'day'
    it 'is initialized with the right interval', ->
      expect(bucket.maxWait).eql 1000 * 60 * 60 * 24

describe 'a tokenbucket with maxWait', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    bucket = new TokenBucket
      size: 10
      tokensLeft: 1
      maxWait: 2000
  afterEach ->
    clock.restore()
  it 'will remove tokens when maxWait is not exceeded', (done) ->
    checkRemoval
      done: done
  it 'will not remove tokens when maxWait is exceeded and reject with the right error', (done) ->
    bucket.removeTokens(10).catch (err) ->
      expect(err instanceof Error).true
      expect(err.name).eql 'ExceedsMaxWait'
      expect(err.message).eql 'It will exceed maximum waiting time'
      done()

describe 'a tokenbucket with maxWait and parent', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    parentBucket = new TokenBucket
      size: 20
      tokensLeft: 1
    bucket = new TokenBucket
      size: 10
      maxWait: 2000
      parentBucket: parentBucket
  afterEach ->
    clock.restore()
  it 'will remove tokens when maxWait is not exceeded', (done) ->
    checkRemoval
      done: done
  it 'will not remove tokens when maxWait is exceeded because of the parent and reject with the right error', (done) ->
    bucket.removeTokens(10).catch (err) ->
      expect(err instanceof Error).true
      expect(err.name).eql 'ExceedsMaxWait'
      expect(err.message).eql 'It will exceed maximum waiting time'
      done()

describe 'a tokenbucket with maxWait and parent with smaller maxWait', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    parentBucket = new TokenBucket
      size: 20
      tokensLeft: 1
      maxWait: 2000
    bucket = new TokenBucket
      size: 10
      maxWait: 100000
      parentBucket: parentBucket
  afterEach ->
    clock.restore()
  it 'will remove tokens when maxWait is not exceeded', (done) ->
    checkRemoval
      done: done
  it 'will not remove tokens when maxWait is exceeded because of the parent and reject with the right error', (done) ->
    bucket.removeTokens(10).catch (err) ->
      expect(err instanceof Error).true
      expect(err.name).eql 'ExceedsMaxWait'
      expect(err.message).eql 'It will exceed maximum waiting time'
      done()

describe 'a tokenbucket with maxWait and parent with bigger maxWait', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    parentBucket = new TokenBucket
      size: 20
      tokensLeft: 1
      maxWait: 100000
    bucket = new TokenBucket
      size: 10
      maxWait: 2000
      parentBucket: parentBucket
  afterEach ->
    clock.restore()
  it 'will remove tokens when maxWait is not exceeded', (done) ->
    checkRemoval
      done: done
  it 'will not remove tokens when maxWait is exceeded because of the child and reject with the right error', (done) ->
    bucket.removeTokens(10).catch (err) ->
      expect(err instanceof Error).true
      expect(err.name).eql 'ExceedsMaxWait'
      expect(err.message).eql 'It will exceed maximum waiting time'
      done()

describe 'a tokenbucket with a parent with maxWait', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    parentBucket = new TokenBucket
      size: 20
      maxWait: 2000
    bucket = new TokenBucket
      size: 10
      tokensLeft: 1
      parentBucket: parentBucket
  afterEach ->
    clock.restore()
  it 'will remove tokens when the parent maxWait is not exceeded', (done) ->
    checkRemoval
      done: done
  it 'will not remove tokens when the parent maxWait is exceeded and reject with the right error', (done) ->
    bucket.removeTokens(10).catch (err) ->
      expect(err instanceof Error).true
      expect(err.name).eql 'ExceedsMaxWait'
      expect(err.message).eql 'It will exceed maximum waiting time'
      done()

describe 'a tokenbucket with a grandparent with maxWait', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    grandParentBucket = new TokenBucket
      size: 50
      maxWait: 2000
    parentBucket = new TokenBucket
      size: 20
      parentBucket: grandParentBucket
    bucket = new TokenBucket
      size: 10
      tokensLeft: 1
      maxWait: 100000
      parentBucket: parentBucket
  afterEach ->
    clock.restore()
  it 'will remove tokens when the parent maxWait is not exceeded', (done) ->
    checkRemoval
      done: done
  it 'will not remove tokens when the grandparent maxWait is exceeded and reject with the right error', (done) ->
    bucket.removeTokens(10).catch (err) ->
      expect(err instanceof Error).true
      expect(err.name).eql 'ExceedsMaxWait'
      expect(err.message).eql 'It will exceed maximum waiting time'
      done()

describe 'an empty tokenbucket size 2 filled evenly and last filled 1s ago when requesting tokens sync', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    bucket = new TokenBucket
      size: 2
      spread: true
      tokensLeft: 0
      lastFill: +new Date() - 1000
  afterEach ->
    clock.restore()
  describe 'when requesting 2 tokens sync', ->
    it 'doesn\'t remove them but add 1 token', ->
      result = bucket.removeTokensSync 2
      expect(result).to.be.false
      expect(bucket.tokensLeft).eql 1
  describe 'when requesting 1 token sync', ->
    it 'removes it and has 0 tokens', ->
      result = bucket.removeTokensSync 1
      expect(result).to.be.true
      expect(bucket.tokensLeft).eql 0
  describe 'removeTokensSync called without parameter', ->
    it 'removes 1 token and has 0 tokens', ->
      result = bucket.removeTokensSync()
      expect(result).to.be.true
      expect(bucket.tokensLeft).eql 0
  describe 'when it has a parent without enough tokens', ->
    it 'doesn\'t remove tokens', ->
      parentBucket = new TokenBucket
        tokensLeft: 0
      bucket.parentBucket = parentBucket
      result = bucket.removeTokensSync()
      expect(result).to.be.false
      expect(bucket.tokensLeft).eql 1
  describe 'when trying to remove more tokens that its size', ->
    it 'doesn\'t remove tokens but adds 1 token', ->
      result = bucket.removeTokensSync(3)
      expect(result).to.be.false
      expect(bucket.tokensLeft).eql 1
  describe 'when waiting 500ms and removing 1 token', ->
    it 'removes the token and leaves 0.5 tokens', ->
      clock.tick 500
      result = bucket.removeTokensSync()
      expect(result).to.be.true
      expect(bucket.tokensLeft).eql 0.5

describe 'a tokenbucket with parent bucket', ->
  parentBucket = null
  before ->
    clock = sinon.useFakeTimers()
    parentBucket = new TokenBucket()
    bucket = new TokenBucket
      size: 2
      parentBucket: parentBucket
  after ->
    clock.restore()
  describe 'when removing a token', ->
    it 'removes it from the bucket and leaves 1 token', (done) ->
      expect(bucket.tokensLeft).eql 2
      expect(bucket.parentBucket.tokensLeft).eql 1
      checkRemoval
        tokensLeft: 1
        done: done
    it 'removes it from the parent bucket and leaves 0 tokens', ->
      expect(parentBucket.tokensLeft).eql 0
    describe 'when removing a token and there are no tokens in the parent', ->
      it 'waits for the parent to have enough tokens and then removes it from bucket and parent bucket', (done) ->
        done = sinon.spy(done)
        expect(bucket.tokensLeft).eql 1
        expect(bucket.parentBucket.tokensLeft).eql 0
        checkRemoval
          tokensLeft: 1 # same interval as the parent, after the wait got 1 more token (2 left), after removal there is 1 left
          parentTokensLeft: 0 # 1 token after interval, 0 tokens after removal
          time: 1000
          clock: clock
          done: done
          nextTickScheduler: true

      describe 'when after waiting for the parent doesn\t have enough tokens any more', ->
        it 'waits to get enough tokens', (done) ->
          done = sinon.spy(done)
          bucket.interval = 1500 # greater interval than the parent, so we check that it waits longer than just the parent interval
          bucket.removeTokens().then ->
            expect(bucket.tokensLeft).eql 0
            expect(bucket.parentBucket.tokensLeft).eql 0
            done()
          clock.tick 500 # some time passed whilst waiting for parent
          expect(bucket.tokensLeft).eql 1 # still one token left
          expect(bucket.parentBucket.tokensLeft).eql 0 # parent still empty
          # empty bucket whilst waiting for parent
          bucket.tokensLeft = 0
          expect(bucket.tokensLeft).eql 0
          expect(bucket.parentBucket.tokensLeft).eql 0
          # the parent gets 1 token (500 + 500 = parent interval)
          clock.tick 500
          # We need nextTick so the previous clock tick gets executed, and that part of the code gets covered
          process.nextTick ->
            expect(bucket.tokensLeft).eql 0
            expect(bucket.parentBucket.tokensLeft).eql 1
            clock.tick 499
            expect(done).not.called
            clock.tick 1 # 1500 total = 1000 parent + 500 itself

describe 'a filled infinite tokenbucket', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    bucket = new TokenBucket
      size: Number.POSITIVE_INFINITY
  afterEach ->
    clock.restore()
  it 'removes tokens inmediately and still has infinite tokens', (done) ->
    checkRemoval
      tokensRemove: 9999
      tokensLeft: Number.POSITIVE_INFINITY
      done: done
  it 'can\'t remove infinite tokens and rejects with the right error', (done) ->
    bucket.removeTokens(Number.POSITIVE_INFINITY).catch (err) ->
      expect(err instanceof Error).true
      expect(err.name).eql 'NoInfinityRemoval'
      expect(err.message).eql 'Not possible to remove infinite tokens.'
      done()

describe 'an empty infinite tokenbucket filled evenly with infinite tokens', ->
  before ->
    clock = sinon.useFakeTimers()
    bucket = new TokenBucket
      size: Number.POSITIVE_INFINITY
      tokensToAddPerInterval: Number.POSITIVE_INFINITY
      tokensLeft: 0
      spread: true
  after ->
    clock.restore()
  it 'removes tokens after at least 1ms and then gets infinite tokens', (done) ->
    checkRemoval
      tokensRemove: 9999
      tokensLeft: Number.POSITIVE_INFINITY
      time: 1
      clock: clock
      done: done

describe 'an empty infinite tokenbucket with 100ms interval', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    bucket = new TokenBucket
      size: Number.POSITIVE_INFINITY
      tokensLeft: 0
      interval: 100
  afterEach ->
    clock.restore()
  describe 'when removing 1 token', ->
    it 'takes 100ms and leaves 0 tokens', (done) ->
      checkRemoval
        tokensLeft: 0
        time: 100
        clock: clock
        done: done


describe 'a tokenbucket with size 10 adding 1 token per 100ms', ->
  describe 'when removing 1 token', ->
    before ->
      clock = sinon.useFakeTimers()
      bucket = new TokenBucket
        size: 10
        interval: 100
    after ->
      clock.restore()
    it 'takes the tokens inmediately and leaves 9 tokens', (done) ->
      checkRemoval
        tokensLeft: 9
        done: done
  describe 'when removing 10 tokens', ->
    before ->
      clock = sinon.useFakeTimers()
      bucket = new TokenBucket
        size: 10
        interval: 100
    after ->
      clock.restore()
    it 'takes the tokens inmediately and leaves 0 tokens', (done) ->
      checkRemoval
        tokensRemove: 10
        tokensLeft: 0
        done: done
    describe 'when removing another 10 tokens', ->
      it 'takes 1 second and leaves 0 tokens again', (done) ->
        checkRemoval
          tokensRemove: 10
          tokensLeft: 0
          time: 1000
          clock: clock
          done: done
      describe 'when waiting 2 seconds and removing 10 tokens', ->
        it 'removes the tokens inmediately and leaves the bucket empty', (done) ->
          clock.tick 2000
          checkRemoval
            tokensRemove: 10
            tokensLeft: 0
            done: done

describe 'a tokenbucket starting empty with size 10 adding 1 token per 100ms', ->
  describe 'when removing 1 token', ->
    before ->
      clock = sinon.useFakeTimers()
      bucket = new TokenBucket
        size: 10
        tokensToAddPerInterval: 1
        interval: 100
        tokensLeft: 0
    after ->
      clock.restore()
    it 'takes 100ms and leaves 0 tokens', (done) ->
      checkRemoval
        tokensLeft: 0
        time: 100
        clock: clock
        done: done
  describe 'when removing 10 tokens', ->
    before ->
      clock = sinon.useFakeTimers()
      bucket = new TokenBucket
        size: 10
        tokensToAddPerInterval: 1
        interval: 100
        tokensLeft: 0
    after ->
      clock.restore()
    it 'takes 1 second and leaves 0 tokens', (done) ->
      checkRemoval
        tokensRemove: 10
        tokensLeft: 0
        time: 1000
        clock: clock
        done: done
    describe 'when removing another 10 tokens', ->
      it 'takes 1 second and leaves 0 tokens again', (done) ->
        checkRemoval
          tokensRemove: 10
          tokensLeft: 0
          time: 1000
          clock: clock
          done: done
    describe 'when waiting 2 seconds and removing 10 tokens', ->
      it 'removes the tokens inmediately and leaves the bucket empty', (done) ->
        clock.tick 2000
        checkRemoval
          tokensRemove: 10
          tokensLeft: 0
          done: done


describe 'a tokenbucket with size 10 adding 5 token per 1 second', ->
  before ->
    clock = sinon.useFakeTimers()
    bucket = new TokenBucket
      size: 10
      tokensToAddPerInterval: 5
      interval: 1000
  after ->
    clock.restore()
  describe 'when removing 10 tokens', ->
    it 'takes them inmediately and leaves 0 tokens', (done) ->
      checkRemoval
        tokensRemove: 10
        tokensLeft: 0
        done: done
    describe 'when removing another 10 tokens', ->
      it 'takes 2s and is empty again', (done) ->
        checkRemoval
          tokensRemove: 10
          tokensLeft: 0
          time: 2000
          clock: clock
          done: done
    describe 'when removing another 1 token', ->
      it 'takes 1s and leave 4 tokens left', (done) ->
        checkRemoval
          tokensLeft: 4
          time: 1000
          clock: clock
          done: done

describe 'a tokenbucket with size 10 adding evenly 5 tokens per 1 second', ->
  before ->
    clock = sinon.useFakeTimers()
    bucket = new TokenBucket
      size: 10
      tokensToAddPerInterval: 5
      interval: 1000
      spread: true
  after ->
    clock.restore()
  describe 'when removing 10 tokens', ->
    it 'takes them inmediately and leaves 0 tokens', (done) ->
      checkRemoval
        tokensRemove: 10
        tokensLeft: 0
        done: done
    describe 'when removing another 10 tokens', ->
      it 'takes 2s and is empty again', (done) ->
        checkRemoval
          tokensRemove: 10
          tokensLeft: 0
          time: 2000
          clock: clock
          done: done
    describe 'when removing another 1 token', ->
      it 'takes 200ms and leaves no tokens', (done) ->
        checkRemoval
          tokensLeft: 0
          time: 200
          clock: clock
          done: done

describe 'a tokenbucket with size 10 and 5 tokens left adding 1 token per 100ms', ->
  beforeEach ->
    clock = sinon.useFakeTimers()
    bucket = new TokenBucket
      size: 10
      tokensToAddPerInterval: 1
      interval: 100
      tokensLeft: 5
  after ->
    clock.restore()
  describe 'when removing 10 token', ->
    it 'takes 500ms and leaves 0 tokens', (done) ->
      checkRemoval
        tokensRemove: 10
        tokensLeft: 0
        time: 500
        clock: clock
        done: done


describe 'saving a tokenbucket', ->
  stub = null
  stubParent = null
  parentBucket = null
  describe 'when initialized without bucket name', ->
    it 'rejects the promise with the right error', (done) ->
      redisClient = mset: ->
      bucket = new TokenBucket
        redis:
          redisClient: redisClient
      bucket.save().catch (err) ->
        expect(err instanceof Error).true
        expect(err.name).eql 'NoRedisOptions'
        expect(err.message).eql 'Redis options missing.'
        done()
  describe 'when initialized with the right options', ->
    beforeEach ->
      redisClient = mset: ->
      bucket = new TokenBucket
        redis:
          bucketName: 'test'
          redisClient: redisClient
      stub = sinon.stub(bucket.redis.redisClient, 'mset')
    it 'redis command is called with the right parameters and resolves the promise', ->
      stub.callsArgWith(4, null, 'OK')
      promise = bucket.save()
      expect(bucket.redis.redisClient.mset).to.have.been.calledWith 'tokenbucket:test:lastFill', bucket.lastFill, 'tokenbucket:test:tokensLeft', bucket.tokensLeft
      expect(promise).to.be.resolved
    it 'when callback has error rejects the promise with the error', ->
      stub.callsArgWith(4, new Error('db err'))
      promise = bucket.save()
      expect(promise).to.be.rejectedWith Error, 'db err'
  describe 'when has parent bucket with redis options', ->
    beforeEach ->
      parentRedisClient = mset: ->
      parentBucket = new TokenBucket
        redis:
          bucketName: 'testParent'
          redisClient: parentRedisClient
      redisClient = mset: ->
      bucket = new TokenBucket
        redis:
          bucketName: 'test'
          redisClient: redisClient
        parentBucket: parentBucket
      stubParent = sinon.stub(parentBucket.redis.redisClient, 'mset').yields(Promise.pending().resolve())
      stub = sinon.stub(bucket.redis.redisClient, 'mset')
    it 'parent bucket gets called with the right parameters, then its save() promise resolves, and then redis command is called in the child bucket with the right parameters and resolves the promise', (done) ->
      stub.callsArgWith(4, null, 'OK')
      stubParent.callsArgWith(4, null, 'OK')
      bucket.save().then ->
        expect(parentBucket.redis.redisClient.mset).to.have.been.calledWith 'tokenbucket:testParent:lastFill', parentBucket.lastFill, 'tokenbucket:testParent:tokensLeft', parentBucket.tokensLeft
        expect(bucket.redis.redisClient.mset).to.have.been.calledWith 'tokenbucket:test:lastFill', bucket.lastFill, 'tokenbucket:test:tokensLeft', bucket.tokensLeft
        done()
    it 'when parent callback has error rejects the promise with the error', ->
      stubParent.callsArgWith(4, new Error('db err parent'))
      expect(bucket.save()).to.be.rejectedWith Error, 'db err parent'

describe 'load a saved tokenbucket', ->
  stub = null
  stubParent = null
  parentBucket = null
  lastFill = +new Date()
  lastFillSaved = +new Date() - 5000
  tokensLeftSaved = 3
  describe 'when initialized without bucket name', ->
    it 'rejects the promise with the right error', (done) ->
      redisClient = mget: ->
      bucket = new TokenBucket
        redis:
          redisClient: redisClient
      bucket.loadSaved().catch (err) ->
        expect(err instanceof Error).true
        expect(err.name).eql 'NoRedisOptions'
        expect(err.message).eql 'Redis options missing.'
        done()
  describe 'when initialized with the right options', ->
    beforeEach ->
      redisClient = mget: ->
      bucket = new TokenBucket
        redis:
          bucketName: 'test'
          redisClient: redisClient
      bucket.lastFill = lastFill
      stub = sinon.stub(bucket.redis.redisClient, 'mget')
    it 'calls the redis command with the right parameters and loads the bucket with the returned data', ->
      stub.callsArgWith 2, null, [lastFillSaved, tokensLeftSaved]
      promise = bucket.loadSaved()
      expect(bucket.redis.redisClient.mget).to.have.been.calledWith 'tokenbucket:test:lastFill', 'tokenbucket:test:tokensLeft'
      expect(promise).to.be.resolved
      expect(bucket.lastFill).to.eql lastFillSaved
      expect(bucket.tokensLeft).to.eql tokensLeftSaved
    it 'leaves the original data if no data is returned', ->
      stub.callsArgWith 2, null, [null, null]
      promise = bucket.loadSaved()
      expect(promise).to.be.resolved
      expect(bucket.lastFill).to.eql lastFill
      expect(bucket.tokensLeft).to.eql 1
    it 'when callback has error rejects the promise with the error', ->
      stub.callsArgWith(2, new Error('db err'))
      promise = bucket.loadSaved()
      expect(promise).to.be.rejectedWith Error, 'db err'
  describe 'when has parent bucket with redis options', ->
    beforeEach ->
      parentRedisClient = mget: ->
      parentBucket = new TokenBucket
        redis:
          bucketName: 'testParent'
          redisClient: parentRedisClient
      redisClient = mget: ->
      bucket = new TokenBucket
        redis:
          bucketName: 'test'
          redisClient: redisClient
        parentBucket: parentBucket
      stubParent = sinon.stub(parentBucket.redis.redisClient, 'mget').yields(Promise.pending().resolve())
      stub = sinon.stub(bucket.redis.redisClient, 'mget')
    it 'parent bucket gets called with the right parameters, then its loadSaved() promise resolves, and then redis command is called in the child bucket with the right parameters and resolves the promise', (done) ->
      stub.callsArgWith(2, null, [lastFillSaved, tokensLeftSaved])
      stubParent.callsArgWith(2, null, [lastFillSaved, tokensLeftSaved])
      bucket.loadSaved().then ->
        expect(parentBucket.redis.redisClient.mget).to.have.been.calledWith 'tokenbucket:testParent:lastFill', 'tokenbucket:testParent:tokensLeft'
        expect(bucket.redis.redisClient.mget).to.have.been.calledWith 'tokenbucket:test:lastFill', 'tokenbucket:test:tokensLeft'
        done()
    it 'when parent callback has error rejects the promise with the error', ->
      stubParent.callsArgWith(2, new Error('db err parent'))
      expect(bucket.loadSaved()).to.be.rejectedWith Error, 'db err parent'
