'use strict'
Promise = require 'bluebird'
redis = require 'redis'
###*
  * @module tokenbucket
  * @desc A flexible rate limiter configurable with different variations of the [Token Bucket algorithm](http://en.wikipedia.org/wiki/Token_bucket), with hierarchy support, and optional persistence in Redis. Useful for limiting API requests, or other tasks that need to be throttled.
  * @author Jesús Carrera [@jesucarr](https://twitter.com/jesucarr) - [frontendmatters.com](http://frontendmatters.com)
  *
  * **Installation**
  * ```
  * npm install tokenbucket
  * ```
  *
  * @example
  * Require the library
  * ```javascript
  * var TokenBucket = require('tokenbucket');
  * ```
  * Create a new tokenbucket instance. See below for possible options.
  * ```javascript
  * var tokenBucket = new TokenBucket();
  * ```
###
###*
  * @class
  * @alias module:tokenbucket
  * @classdesc The class that the module exports and that instantiate a new token bucket with the given options.
  *
  * @param {Object} [options] - The options object
  * @param {Number} [options.size=1] - Maximum number of tokens to hold in the bucket. Also known as the burst size.
  * @param {Number} [options.tokensToAddPerInterval=1] - Number of tokens to add to the bucket in one interval.
  * @param {Number|String} [options.interval=1000] - The time passing between adding tokens, in milliseconds or as one of the following strings: 'second', 'minute', 'hour', day'.
  * @param {Number} [options.lastFill]  - The timestamp of the last time when tokens where added to the bucket (last interval).
  * @param {Number} [options.tokensLeft=size] - By default it will initialize full of tokens, but you can set here the number of tokens you want to initialize it with.
  * @param {Boolean} [options.spread=false] - By default it will wait the interval, and then add all the tokensToAddPerInterval at once. If you set this to true, it will insert fractions of tokens at any given time, spreading the token addition along the interval.
  * @param {Number|String} [options.maxWait] - The maximum time that we would wait for enough tokens to be added, in milliseconds or as one of the following strings: 'second', 'minute', 'hour', day'. If any of the parents in the hierarchy has `maxWait`, we will use the smallest value.
  * @param {TokenBucket} [options.parentBucket] - A token bucket that will act as the parent of this bucket. Tokens removed in the children, will also be removed in the parent, and if the parent reach its limit, the children will get limited too.
  * @param {Object} [options.redis] - Options object for Redis
  * @param {String} options.redis.bucketName - The name of the bucket to reference it in Redis. This is the only required field to set Redis persistance. The `bucketName` for each bucket **must be unique**.
  * @param {external:redisClient} [options.redis.redisClient] - The [Redis client](https://github.com/mranney/node_redis#rediscreateclient) to save the bucket.
  * @param {Object} [options.redis.redisClientConfig] - [Redis client configuration](https://github.com/mranney/node_redis#rediscreateclient) to create the Redis client and save the bucket. If the `redisClient` option is set, this option will be ignored.
  * @param {Number} [options.redis.redisClientConfig.port=6379] - The connection port for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient).
  * @param {String} [options.redis.redisClientConfig.host='127.0.0.1'] - The connection host for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient)
  * @param {String} [options.redis.redisClientConfig.unixSocket] - The connection unix socket for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient)
  * @param {String} [options.redis.redisClientConfig.options] - The options for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient)
  *
  * This options will be properties of the class instances. The properties `tokensLeft` and `lastFill` will get updated when we add/remove tokens.
  *
  * @example
  *
  * A filled token bucket that can hold 100 tokens, and it will add 30 tokens every minute (all at once).
  * ```javascript
  * var tokenBucket = new TokenBucket({
  *   size: 100,
  *   tokensToAddPerInterval: 30,
  *   interval: 'minute'
  * });
  * ```
  * An empty token bucket that can hold 1 token (default), and it will add 1 token (default) every 500ms, spreading the token addition along the interval (so after 250ms it will have 0.5 tokens).
  * ```javascript
  * var tokenBucket = new TokenBucket({
  *   tokensLeft: 0,
  *   interval: 500,
  *   spread: true
  * });
  * ```
  * A token bucket limited to 15 requests every 15 minutes, with a parent bucket limited to 1000 requests every 24 hours. The maximum time that we are willing to wait for enough tokens to be added is one hour.
  * ```javascript
  * var parentTokenBucket = new TokenBucket({
  *   size: 1000,
  *   interval: 'day'
  * });
  * var tokenBucket = new TokenBucket({
  *   size: 15,
  *   tokensToAddPerInterval: 15,
  *   interval: 'minute',
  *   maxWait: 'hour',
  *   parentBucket: parentBucket
  * });
  * ```
  * A token bucket limited to 15 requests every 15 minutes, with a parent bucket limited to 1000 requests every 24 hours. The maximum time that we are willing to wait for enough tokens to be added is 5 minutes.
  * ```javascript
  * var parentTokenBucket = new TokenBucket({
  *   size: 1000,
  *   interval: 'day'
  *   maxWait: 1000 * 60 * 5,
  * });
  * var tokenBucket = new TokenBucket({
  *   size: 15,
  *   tokensToAddPerInterval: 15,
  *   interval: 'minute',
  *   parentBucket: parentBucket
  * });
  * ```
  * A token bucket with Redis persistance setting the redis client.
  * ```javascript
  * redis = require('redis');
  * redisClient = redis.redisClient();
  * var tokenBucket = new TokenBucket({
  *   redis: {
  *     bucketName: 'myBucket',
  *     redisClient: redisClient
  *   }
  * });
  * ```
  * A token bucket with Redis persistance setting the redis configuration.
  * ```javascript
  * var tokenBucket = new TokenBucket({
  *   redis: {
  *     bucketName: 'myBucket',
  *     redisClientConfig: {
  *       host: 'myhost',
  *       port: 1000,
  *       options: {
  *         auth_pass: 'mypass'
  *       }
  *     }
  *   }
  * });
  * ```
  * Note that setting both `redisClient` or `redisClientConfig`, the redis client will be exposed at `tokenBucket.redis.redisClient`.
  * This means you can watch for redis events, or execute redis client functions.
  * For example if we want to close the redis connection we can execute `tokenBucket.redis.redisClient.quit()`.
###

class TokenBucket

  # Private members

  errors =
    noRedisOptions: 'Redis options missing.'
    notEnoughSize: (tokensToRemove, size) -> 'Requested tokens (' + tokensToRemove + ') exceed bucket size (' + size + ')'
    noInfinityRemoval: 'Not possible to remove infinite tokens.'
    exceedsMaxWait: 'It will exceed maximum waiting time'

  # Add new tokens to the bucket if possible.
  addTokens = ->
    now = +new Date()
    timeSinceLastFill = Math.max(now - @lastFill, 0)
    if timeSinceLastFill
      tokensSinceLastFill = timeSinceLastFill * (@tokensToAddPerInterval / @interval)
    else
      tokensSinceLastFill = 0
    if @spread or (timeSinceLastFill >= @interval)
      @lastFill = now
      @tokensLeft = Math.min(@tokensLeft + tokensSinceLastFill, @size)

  constructor: (config) ->
    {@size, @tokensToAddPerInterval, @interval, @tokensLeft, @lastFill, @spread, @redis, @parentBucket, @maxWait} = config if config
    if @redis? and @redis.bucketName?
      if @redis.redisClient?
        delete @redis.redisClientConfig
      else
        @redis.redisClientConfig ?= {}
        if @redis.redisClientConfig.unixSocket?
          @redis.redisClient = redis.createClient @redis.redisClientConfig.unixSocket, @redis.redisClientConfig.options
        else
          @redis.redisClientConfig.port ?= 6379
          @redis.redisClientConfig.host ?= '127.0.0.1'
          @redis.redisClientConfig.options ?= {}
          @redis.redisClient = redis.createClient @redis.redisClientConfig.port, @redis.redisClientConfig.host, @redis.redisClientConfig.options
    else
      delete @redis
    if @size != Number.POSITIVE_INFINITY then @size ?= 1
    @tokensLeft ?= @size
    @tokensToAddPerInterval ?= 1
    if !@interval?
      @interval = 1000
    else if typeof @interval == 'string'
      switch @interval
        when 'second' then @interval = 1000
        when 'minute' then @interval = 1000 * 60
        when 'hour' then @interval = 1000 * 60 * 60
        when 'day' then @interval = 1000 * 60 * 60 * 24
    if typeof @maxWait == 'string'
      switch @maxWait
        when 'second' then @maxWait = 1000
        when 'minute' then @maxWait = 1000 * 60
        when 'hour' then @maxWait = 1000 * 60 * 60
        when 'day' then @maxWait = 1000 * 60 * 60 * 24
    @lastFill ?= +new Date()

  # Public API

  ###*
    * @desc Remove the requested number of tokens. If the bucket (and any parent buckets) contains enough tokens this will happen immediately. Otherwise, it will wait to get enough tokens.
    * @param {Number} tokensToRemove - The number of tokens to remove.
    * @returns {external:Promise}
    * @fulfil {Number} - The remaining tokens number, taking into account the parent if it has it.
    * @reject {Error} - Operational errors will be returned with the following `name` property, so they can be handled accordingly:
    * * `'NotEnoughSize'` - The requested tokens are greater than the bucket size.
    * * `'NoInfinityRemoval'` - It is not possible to remove infinite tokens, because even if the bucket has infinite size, the `tokensLeft` would be indeterminant.
    * * `'ExceedsMaxWait'` - The time we need to wait to be able to remove the tokens requested exceed the time set in `maxWait` configuration (parent or child).
    *
    * .
    * @example
    * We have some code that uses 3 API requests, so we would need to remove 3 tokens from our rate limiter bucket.
    * If we had to wait more than the specified `maxWait` to get enough tokens, we would handle that in certain way.
    * ```javascript
    * tokenBucket.removeTokens(3).then(function(remainingTokens) {
    *    console.log('10 tokens removed, ' + remainingTokens + 'tokens left');
    *    // make triple API call
    * }).catch(function (err) {
    *   console.log(err)
    *   if (err.name === 'ExceedsMaxWait') {
    *      // do something to handle this specific error
    *   }
    * });
    * ```
  ###
  removeTokens: (tokensToRemove) =>
    resolver = Promise.pending()
    tokensToRemove ||= 1
    # Make sure the bucket can hold the requested number of tokens
    if tokensToRemove > @size
      error = new Error(errors.notEnoughSize tokensToRemove, @size)
      Object.defineProperty error, 'name', {value: 'NotEnoughSize'}
      resolver.reject error
      return resolver.promise
    # Not possible to remove infitine tokens because even if the bucket has infinite size, the tokensLeft would be indeterminant
    if tokensToRemove == Number.POSITIVE_INFINITY
      error = new Error errors.noInfinityRemoval
      Object.defineProperty error, 'name', {value: 'NoInfinityRemoval'}
      resolver.reject error
      return resolver.promise
    # Add new tokens into this bucket if necessary
    addTokens.call(@)
    # Calculates the waiting time necessary to get enough tokens for the specified bucket
    calculateWaitInterval = (bucket) ->
      tokensNeeded = tokensToRemove - bucket.tokensLeft
      timeSinceLastFill = Math.max(+new Date() - bucket.lastFill, 0)
      if bucket.spread
        timePerToken = bucket.interval / bucket.tokensToAddPerInterval
        waitInterval = Math.ceil(tokensNeeded * timePerToken - timeSinceLastFill)
      else
        # waitInterval = @interval - timeSinceLastFill
        intervalsNeeded = tokensNeeded / bucket.tokensToAddPerInterval
        waitInterval = Math.ceil(intervalsNeeded * bucket.interval - timeSinceLastFill)
      Math.max(waitInterval, 0)
    # Calculate the wait time to get enough tokens taking into account the parents
    bucketWaitInterval = calculateWaitInterval(@)
    hierarchyWaitInterval = bucketWaitInterval
    if @maxWait? then hierarchyMaxWait = @maxWait
    parentBucket = @parentBucket
    while parentBucket?
      hierarchyWaitInterval += calculateWaitInterval(parentBucket)
      if parentBucket.maxWait?
        if hierarchyMaxWait?
          hierarchyMaxWait = Math.min(parentBucket.maxWait, hierarchyMaxWait)
        else
          hierarchyMaxWait = parentBucket.maxWait
      parentBucket = parentBucket.parentBucket
    # If we need to wait longer than maxWait, reject with the right error
    if hierarchyMaxWait? and (hierarchyWaitInterval > hierarchyMaxWait)
      error = new Error errors.exceedsMaxWait
      Object.defineProperty error, 'name', {value: 'ExceedsMaxWait'}
      resolver.reject error
      return resolver.promise
    # Times out to get enough tokens
    wait = =>
      waitResolver = Promise.pending()
      setTimeout ->
        waitResolver.resolve(true)
      , bucketWaitInterval
      waitResolver.promise
    # If we don't have enough tokens in this bucket, wait to get them
    if tokensToRemove > @tokensLeft
      return wait().then =>
        @removeTokens tokensToRemove
    else
      if @parentBucket
        # Remove the requested tokens from the parent bucket first
        parentLastFill = @parentBucket.lastFill
        return @parentBucket.removeTokens tokensToRemove
          .then =>
            # Add tokens after the wait for the parent
            addTokens.call(@)
            # Check that we still have enough tokens in this bucket, if not, reset removal from parent, wait for tokens, and start over
            if tokensToRemove > @tokensLeft
              @parentBucket.tokensLeft += tokensToRemove
              @parentBucket.lastFill = parentLastFill
              return wait().then =>
                @removeTokens tokensToRemove
            else
              # Tokens were removed from the parent bucket, now remove them from this bucket and return
              @tokensLeft -= tokensToRemove
              return Math.min @tokensLeft, @parentBucket.tokensLeft
      else
        # Remove the requested tokens from this bucket and resolve
        @tokensLeft -= tokensToRemove
        resolver.resolve(@tokensLeft)
    resolver.promise

  ###*
    * @desc Attempt to remove the requested number of tokens and return inmediately.
    * @param {Number} tokensToRemove - The number of tokens to remove.
    * @returns {Boolean} If it could remove the tokens inmediately it will return `true`, if not possible or needs to wait, it will return `false`.
    *
    * @example
    * ```javascript
    * if (tokenBucket.removeTokensSync(50)) {
    *   // the tokens were removed
    * } else {
    *   // the tokens were not removed
    * }
    * ```
  ###
  removeTokensSync: (tokensToRemove) =>
    tokensToRemove ||= 1
    # Add new tokens into this bucket if necessary
    addTokens.call(@)
    # Make sure the bucket can hold the requested number of tokens
    if tokensToRemove > @size then return false
    # If we don't have enough tokens in this bucket, return false
    if tokensToRemove > @tokensLeft then return false
    # Try to remove the requested tokens from the parent bucket
    if @parentBucket and !@parentBucket.removeTokensSync tokensToRemove then return false
    # Remove the requested tokens from this bucket and return
    @tokensLeft -= tokensToRemove
    true

  ###*
    * @desc Saves the bucket lastFill and tokensLeft to Redis. If it has any parents with `redis` options, they will get saved too.
    *
    * @returns {external:Promise}
    * @fulfil {true}
    * @reject {Error} - If we call this function and we didn't set the redis options, the error will have `'NoRedisOptions'` as the `name` property, so it can be handled specifically.
    * If there is an error with Redis it will be rejected with the error returned by Redis.
    * @example
    * We have a worker process that uses 1 API requests, so we would need to remove 1 token (default) from our rate limiter bucket.
    * If we had to wait more than the specified `maxWait` to get enough tokens, we would end the worker process.
    * We are saving the bucket state in Redis, so we first load from Redis, and before exiting we save the updated bucket state.
    * Note that if it had parent buckets with Redis options set, they would get saved too.
    * ```javascript
    * tokenBucket.loadSaved().then(function () {
    *   // now the bucket has the state it had last time we saved it
    *   return tokenBucket.removeTokens().then(function() {
    *      // make API call
    *   });
    * }).catch(function (err) {
    *   if (err.name === 'ExceedsMaxWait') {
    *     tokenBucket.save().then(function () {
    *       process.kill(process.pid, 'SIGKILL');
    *     }).catch(function (err) {
    *       if (err.name == 'NoRedisOptions') {
    *         // do something to handle this specific error
    *       }
    *     });
    *   }
    * });
    * ```
  ###
  save: =>
    resolver = Promise.pending()
    if !@redis
      error = new Error errors.noRedisOptions
      Object.defineProperty error, 'name', {value: 'NoRedisOptions'}
      resolver.reject error
    else
      set = =>
        @redis.redisClient.mset 'tokenbucket:' + @redis.bucketName + ':lastFill', @lastFill, 'tokenbucket:' + @redis.bucketName + ':tokensLeft', @tokensLeft, (err, reply) ->
          if err
            resolver.reject new Error err
          else
            resolver.resolve(true)
      if @parentBucket and @parentBucket.redis?
        return @parentBucket.save().then set
      else
        set()
    resolver.promise

  ###*
    * @desc Loads the bucket lastFill and tokensLeft as it was saved in Redis. If it has any parents with `redis` options, they will get loaded too.
    * @returns {external:Promise}
    * @fulfil {true}
    * @reject {Error} - If we call this function and we didn't set the redis options, the error will have `'NoRedisOptions'` as the `name` property, so it can be handled specifically.
    * If there is an error with Redis it will be rejected with the error returned by Redis.
    * @example @lang off
    * See {@link module:tokenbucket#save}
  ###
  loadSaved: =>
    resolver = Promise.pending()
    if !@redis
      error = new Error errors.noRedisOptions
      Object.defineProperty error, 'name', {value: 'NoRedisOptions'}
      resolver.reject error
    else
      get = =>
        @redis.redisClient.mget 'tokenbucket:' + @redis.bucketName + ':lastFill', 'tokenbucket:' + @redis.bucketName + ':tokensLeft', (err, reply) =>
          if err
            resolver.reject new Error err
          else
            @lastFill = +reply[0] if reply[0]
            @tokensLeft = +reply[1] if reply[1]
            resolver.resolve(true)
      if @parentBucket and @parentBucket.redis?
        return @parentBucket.loadSaved().then get
      else
        get()
    resolver.promise

module.exports = TokenBucket

###*
  * @external Promise
  * @see https://github.com/petkaantonov/bluebird
###
###*
  * @external redisClient
  * @see https://github.com/mranney/node_redis#rediscreateclient
###
###*
  * @external redisClientCofig
  * @see https://github.com/mranney/node_redis#rediscreateclient
###
